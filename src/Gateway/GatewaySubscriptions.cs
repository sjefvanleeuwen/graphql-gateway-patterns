using Common.Auth;
using HotChocolate;
using HotChocolate.Types;

namespace Gateway;

public class GatewaySubscriptions
{
    [Subscribe]
    [Topic("GatewayReloaded")]
    public string OnGatewayReloaded([EventMessage] string message) => message;

    [Subscribe]
    [Topic("AuthorizationReloaded")]
    public AuthorizationReloadedMessage OnAuthorizationReloaded([EventMessage] AuthorizationReloadedMessage message) => message;
}
