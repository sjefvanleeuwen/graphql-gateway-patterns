using Shouldly;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace NitroSchemaApi.Tests;

public class IntegrationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public IntegrationTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:postgres", "Host=localhost;Database=test;Username=test;Password=test");
            builder.UseSetting("Nitro:AdminToken", "test-token");
        });
    }

    [Fact]
    public async Task HealthEndpoint_ShouldReturnHealthy()
    {
        // Arrange
        var client = _factory.CreateClient();

        // Act
        var response = await client.GetAsync("/health");

        // Assert
        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync();
        content.ShouldBe("\"healthy\"");
    }

    [Fact]
    public async Task RootEndpoint_ShouldReturnStatus()
    {
        // Arrange
        var client = _factory.CreateClient();

        // Act
        var response = await client.GetAsync("/");

        // Assert
        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync();
        content.ShouldContain("nitro-schema-api");
        content.ShouldContain("running");
    }
}
