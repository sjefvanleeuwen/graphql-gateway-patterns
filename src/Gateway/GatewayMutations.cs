using HotChocolate;
using System.Security.Cryptography;
using System.Text;

namespace Gateway;

public sealed class GatewayMutations
{
    /// <summary>
    /// Publishes a new Fusion Gateway Package (FGP) to the gateway.
    /// This triggers a hot-reload of the gateway configuration without downtime.
    /// Requires a valid admin token.
    /// </summary>
    /// <param name="fgpBase64">The base64-encoded content of the gateway.fgp file.</param>
    /// <param name="token">The administrative token for authentication.</param>
    /// <param name="publisher">The service responsible for distributing the schema.</param>
    /// <param name="config">Configuration to validate the token.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>True if the publication was successful.</returns>
    public async Task<bool> PublishGatewayFgp(
        string fgpBase64,
        string token,
        [Service] INitroSchemaPublisher publisher,
        [Service] IConfiguration config,
        CancellationToken cancellationToken)
    {
        var expected = config["Nitro:AdminToken"]
                       ?? Environment.GetEnvironmentVariable("NITRO_ADMIN_TOKEN")
                       ?? string.Empty;

        if (string.IsNullOrWhiteSpace(expected))
        {
            throw new GraphQLException(ErrorBuilder.New().SetMessage("Publishing disabled").SetCode("PUBLISHING_DISABLED").Build());
        }

        if (string.IsNullOrWhiteSpace(token))
        {
            throw new GraphQLException(ErrorBuilder.New().SetMessage("Missing token").SetCode("AUTH_MISSING").Build());
        }

        if (!TokensMatch(expected, token))
        {
            throw new GraphQLException(ErrorBuilder.New().SetMessage("Invalid token").SetCode("AUTH_INVALID").Build());
        }

        if (string.IsNullOrWhiteSpace(fgpBase64))
        {
            throw new GraphQLException(ErrorBuilder.New().SetMessage("Missing fgpBase64").SetCode("FGP_MISSING").Build());
        }

        try
        {
            await publisher.PublishAsync(fgpBase64, token, cancellationToken);
            return true;
        }
        catch (InvalidOperationException ex)
        {
            throw new GraphQLException(
                ErrorBuilder.New()
                    .SetMessage($"Nitro is not connected: {ex.Message}")
                    .SetCode("NITRO_UNAVAILABLE")
                    .Build());
        }
    }

    private static bool TokensMatch(string expected, string provided)
    {
        var a = Encoding.UTF8.GetBytes(expected ?? string.Empty);
        var b = Encoding.UTF8.GetBytes(provided ?? string.Empty);

        if (a.Length != b.Length)
        {
            return false;
        }

        return CryptographicOperations.FixedTimeEquals(a, b);
    }
}
