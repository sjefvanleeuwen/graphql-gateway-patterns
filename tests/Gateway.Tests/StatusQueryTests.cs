using System.IO.Compression;
using System.Text;
using System.Text.Json;
using Shouldly;
using Gateway;
using Microsoft.Extensions.Hosting;
using Moq;
using Xunit;

namespace Gateway.Tests;

public class StatusQueryTests : IDisposable
{
    private readonly string _tempDir;
    private readonly string _fgpPath;

    public StatusQueryTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(_tempDir);
        _fgpPath = Path.Combine(_tempDir, "gateway.fgp");
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, true);
        }
    }

    [Fact]
    public async Task GetSubgraphs_ShouldParseFgpFile()
    {
        // Arrange
        CreateDummyFgp(_fgpPath);
        
        var envMock = new Mock<IHostEnvironment>();
        envMock.Setup(x => x.ContentRootPath).Returns(_tempDir);

        var query = new StatusQuery();

        // Act
        var result = await query.GetSubgraphs(envMock.Object);

        // Assert
        result.ShouldNotBeNull();
        result.Count().ShouldBe(1);
        result.First().Name.ShouldBe("products");
        result.First().Url.ShouldBe("http://products/graphql");
    }

    private void CreateDummyFgp(string path)
    {
        using var stream = File.Create(path);
        using var archive = new ZipArchive(stream, ZipArchiveMode.Create);
        
        var entry = archive.CreateEntry("v1/subgraphs/products/subgraph-config.json");
        using var entryStream = entry.Open();
        
        var json = JsonSerializer.Serialize(new
        {
            subgraph = "products",
            http = new { baseAddress = "http://products/graphql" }
        });
        
        entryStream.Write(Encoding.UTF8.GetBytes(json));
    }
}
