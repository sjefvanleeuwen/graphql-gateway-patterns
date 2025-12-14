using HotChocolate;
using System.Security.Cryptography;
using System.Text;

namespace Gateway;

public sealed class GatewayMutations
{
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
