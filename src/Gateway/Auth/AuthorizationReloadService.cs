using Common.Auth;
using HotChocolate.Subscriptions;
using Microsoft.Extensions.Options;

namespace Gateway.Auth;

/// <summary>
/// Background service that watches for authorization configuration changes
/// and notifies subscribers via WebSocket when policies are reloaded.
/// </summary>
public class AuthorizationReloadService : BackgroundService
{
    private readonly IOptionsMonitor<AuthorizationConfig> _optionsMonitor;
    private readonly ITopicEventSender _sender;
    private readonly ILogger<AuthorizationReloadService> _logger;
    private readonly string _configPath;
    private IDisposable? _changeListener;

    public AuthorizationReloadService(
        IOptionsMonitor<AuthorizationConfig> optionsMonitor,
        ITopicEventSender sender,
        ILogger<AuthorizationReloadService> logger,
        IHostEnvironment env)
    {
        _optionsMonitor = optionsMonitor;
        _sender = sender;
        _logger = logger;
        _configPath = System.IO.Path.Combine(env.ContentRootPath, "appsettings.json");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Subscribe to configuration changes via IOptionsMonitor
        _changeListener = _optionsMonitor.OnChange(OnConfigurationChanged);

        // Also watch the file for changes (belt and suspenders approach)
        var directory = System.IO.Path.GetDirectoryName(_configPath);
        if (directory != null && Directory.Exists(directory))
        {
            _logger.LogInformation("Watching for authorization policy changes in: {Path}", _configPath);

            using var watcher = new FileSystemWatcher(directory)
            {
                Filter = "appsettings*.json",
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.CreationTime | NotifyFilters.Size,
                EnableRaisingEvents = true
            };

            watcher.Changed += OnFileChanged;
            watcher.Created += OnFileChanged;

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
                watcher.Changed -= OnFileChanged;
                watcher.Created -= OnFileChanged;
            }
        }
        else
        {
            _logger.LogWarning("Configuration directory not found: {Directory}", directory);
            await Task.Delay(Timeout.Infinite, stoppingToken);
        }
    }

    private void OnConfigurationChanged(AuthorizationConfig config, string? name)
    {
        _logger.LogInformation("Authorization configuration changed. Policy count: {Count}", config.Policies.Count);
        NotifySubscribers("Configuration change detected via IOptionsMonitor");
    }

    private void OnFileChanged(object sender, FileSystemEventArgs e)
    {
        _logger.LogInformation("Detected change in {FileName}. Authorization policies will be reloaded.", e.Name);
        NotifySubscribers($"File change detected: {e.Name}");
    }

    private void NotifySubscribers(string trigger)
    {
        var config = _optionsMonitor.CurrentValue;
        var policyNames = string.Join(", ", config.Policies.Keys);
        
        var message = new AuthorizationReloadedMessage(
            DateTime.UtcNow,
            config.Policies.Count,
            config.Policies.Keys.ToArray(),
            trigger
        );

        _sender.SendAsync("AuthorizationReloaded", message);
        _logger.LogInformation("Authorization policies reloaded. Available policies: {Policies}", policyNames);
    }

    public override void Dispose()
    {
        _changeListener?.Dispose();
        base.Dispose();
    }
}
