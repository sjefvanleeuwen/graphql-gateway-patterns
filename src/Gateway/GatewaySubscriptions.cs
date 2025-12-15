using HotChocolate;
using HotChocolate.Types;

namespace Gateway;

public class GatewaySubscriptions
{
    /// <summary>
    /// Subscribes to gateway reload events.
    /// Clients will receive a message whenever the gateway configuration is updated (e.g., via PublishGatewayFgp).
    /// </summary>
    /// <param name="message">The reload message.</param>
    /// <returns>The message content.</returns>
    [Subscribe]
    [Topic("GatewayReloaded")]
    public string OnGatewayReloaded([EventMessage] string message) => message;
}
