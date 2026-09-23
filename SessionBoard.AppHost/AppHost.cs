var builder = DistributedApplication.CreateBuilder(args);

// Pin the http launch profile (it carries ASPNETCORE_ENVIRONMENT=Development) but
// let Aspire pick the proxy port: a fixed applicationUrl port can land inside a
// Windows excluded port range, and then the endpoint silently never listens.
builder.AddProject<Projects.SessionBoard_Api>("sessionboard-api", launchProfileName: "http")
    .WithEndpoint("http", endpoint => endpoint.Port = null)
    .WithUrlForEndpoint("http", _ => new() { Url = "/scalar", DisplayText = "Scalar API reference" });

builder.Build().Run();
