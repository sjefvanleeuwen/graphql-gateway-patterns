using HotChocolate.Execution;
using HotChocolate.Subscriptions;

namespace Gateway;

public class FusionReloadService : BackgroundService
{
    private readonly IRequestExecutorResolver _executorResolver;
    private readonly ITopicEventSender _sender;
    private readonly ILogger<FusionReloadService> _logger;
    private readonly string _filePath;

    public FusionReloadService(IRequestExecutorResolver executorResolver, ITopicEventSender sender, ILogger<FusionReloadService> logger, IHostEnvironment env)
    {
        _executorResolver = executorResolver;
        _sender = sender;
        _logger = logger;
        _filePath = System.IO.Path.Combine(env.ContentRootPath, "gateway.fgp");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var directory = System.IO.Path.GetDirectoryName(_filePath);
        var fileName = System.IO.Path.GetFileName(_filePath);

        if (directory == null || !Directory.Exists(directory))
        {
            _logger.LogWarning($"Directory for gateway.fgp not found: {directory}");
            return;
        }

        _logger.LogInformation($"Watching for changes in: {_filePath}");

        using var watcher = new FileSystemWatcher(directory, fileName)
        {
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.CreationTime | NotifyFilters.Size,
            EnableRaisingEvents = true
        };

        watcher.Changed += OnChanged;
        watcher.Created += OnChanged;
        watcher.Renamed += OnChanged;

        try
        {
            await Task.Delay(Timeout.Infinite, stoppingToken);
        }
        catch (OperationCanceledException)
        {
            // Graceful shutdown
        }
        finally
        {
            watcher.Changed -= OnChanged;
            watcher.Created -= OnChanged;
            watcher.Renamed -= OnChanged;
        }
    }

    private void OnChanged(object sender, FileSystemEventArgs e)
    {
        // Debounce slightly to avoid multiple events for the same write
        _logger.LogInformation($"Detected change in {e.Name}. Reloading Gateway configuration...");
        
        // Evicting the default executor forces Hot Chocolate to rebuild the schema 
        // (and re-read the configuration) on the next request.
        _executorResolver.EvictRequestExecutor();

        // Notify subscribers
        _sender.SendAsync("GatewayReloaded", $"Gateway configuration reloaded at {DateTime.Now}");
    }
}
