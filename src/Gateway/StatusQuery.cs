using System.IO.Compression;
using System.Text.Json;

namespace Gateway;

public class StatusQuery
{
    /// <summary>
    /// Returns the current operational status of the Gateway.
    /// </summary>
    public string Status => "Running";

    /// <summary>
    /// Inspects the currently loaded Fusion Gateway Package (FGP) and returns details about the composed subgraphs.
    /// Useful for verifying which services are currently part of the federated graph.
    /// </summary>
    /// <param name="env">The host environment to locate the FGP file.</param>
    /// <returns>A list of subgraphs with their names and downstream URLs.</returns>
    public async Task<List<SubgraphInfo>> GetSubgraphs([Service] IHostEnvironment env)
    {
        var path = System.IO.Path.Combine(env.ContentRootPath, "gateway.fgp");
        if (!File.Exists(path))
        {
            return new List<SubgraphInfo>();
        }

        var subgraphs = new List<SubgraphInfo>();

        try 
        {
            using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            using var archive = new ZipArchive(stream, ZipArchiveMode.Read);
            
            foreach (var entry in archive.Entries)
            {
                // Look for subgraph configurations
                // Structure is typically v1/subgraphs/<name>/subgraph-config.json
                if (entry.FullName.EndsWith("subgraph-config.json", StringComparison.OrdinalIgnoreCase))
                {
                    using var entryStream = entry.Open();
                    var doc = await JsonDocument.ParseAsync(entryStream);
                    var root = doc.RootElement;
                    
                    string? name = null;
                    string? url = null;

                    if (root.TryGetProperty("subgraph", out var nameProp))
                    {
                        name = nameProp.GetString();
                    }
                    
                    if (root.TryGetProperty("http", out var httpProp))
                    {
                        if (httpProp.TryGetProperty("baseAddress", out var baseAddressProp))
                        {
                            url = baseAddressProp.GetString();
                        }
                        else if (httpProp.TryGetProperty("url", out var urlProp))
                        {
                            url = urlProp.GetString();
                        }
                    }
                    
                    if (name != null)
                    {
                        subgraphs.Add(new SubgraphInfo(name, url));
                    }
                }
            }
        }
        catch (Exception ex)
        {
            subgraphs.Add(new SubgraphInfo("Error", ex.Message));
        }
        
        return subgraphs;
    }
}

public record SubgraphInfo(string? Name, string? Url);
