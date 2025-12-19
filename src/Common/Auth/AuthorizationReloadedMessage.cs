namespace Common.Auth;

/// <summary>
/// Message sent via WebSocket when authorization is reloaded.
/// </summary>
public record AuthorizationReloadedMessage(
    DateTime ReloadedAt,
    int PolicyCount,
    string[] PolicyNames,
    string Trigger
);
