using System.Text.Json;
using Azure;
using Azure.Core;
using Azure.Identity;
using Azure.Messaging.EventGrid;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using Microsoft.Azure.Cosmos;
using Microsoft.Data.SqlClient;
using Azure.Monitor.OpenTelemetry.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry().UseAzureMonitor();
builder.Services.AddSingleton<TokenCredential, DefaultAzureCredential>();
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var credential = sp.GetRequiredService<TokenCredential>();
    var accountName = config["Storage:AccountName"]!;
    return new BlobServiceClient(new Uri($"https://{accountName}.blob.core.windows.net"), credential);
});
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var credential = sp.GetRequiredService<TokenCredential>();
    return new ServiceBusClient(config["ServiceBus:Namespace"], credential);
});
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var credential = sp.GetRequiredService<TokenCredential>();
    return new CosmosClient(config["Cosmos:Endpoint"], credential);
});
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var credential = sp.GetRequiredService<TokenCredential>();
    return new EventGridPublisherClient(new Uri(config["EventGrid:TopicEndpoint"]!), credential);
});

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.MapPost("/orders", async (
    CreateOrderRequest request,
    IConfiguration config,
    ILoggerFactory loggerFactory,
    BlobServiceClient blobs,
    ServiceBusClient serviceBus,
    CosmosClient cosmos,
    EventGridPublisherClient eventGrid,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.CustomerId) ||
        string.IsNullOrWhiteSpace(request.Sku) ||
        request.Quantity <= 0)
    {
        return Results.BadRequest(new { error = "CustomerId, Sku, and a positive Quantity are required." });
    }

    var logger = loggerFactory.CreateLogger("OrderApi");
    var order = new OrderDocument(
        Id: Guid.NewGuid().ToString("n"),
        CustomerId: request.CustomerId,
        Sku: request.Sku,
        Quantity: request.Quantity,
        Status: "Accepted",
        CreatedUtc: DateTimeOffset.UtcNow);

    await EnsureSqlSchemaAsync(config, cancellationToken);
    await InsertSqlOrderAsync(config, order, cancellationToken);

    var database = cosmos.GetDatabase(config["Cosmos:Database"]);
    var container = database.GetContainer(config["Cosmos:Container"]);
    var document = new
    {
        id = order.Id,
        customerId = request.CustomerId,
        sku = request.Sku,
        quantity = request.Quantity,
        createdUtc = order.CreatedUtc
    };
    await container.UpsertItemAsync(document, new PartitionKey(document.customerId), cancellationToken: cancellationToken);

    var blobContainer = blobs.GetBlobContainerClient(config["Storage:PayloadContainer"]);
    await blobContainer.CreateIfNotExistsAsync(cancellationToken: cancellationToken);
    var blob = blobContainer.GetBlobClient($"{order.Id}.json");
    await blob.UploadAsync(BinaryData.FromObjectAsJson(order), overwrite: true, cancellationToken);

    var sender = serviceBus.CreateSender(config["ServiceBus:QueueName"]);
    await sender.SendMessageAsync(new ServiceBusMessage(BinaryData.FromObjectAsJson(order))
    {
        MessageId = order.Id,
        Subject = "orders.created",
        CorrelationId = order.Id
    }, cancellationToken);

    await eventGrid.SendEventAsync(new EventGridEvent(
        subject: $"orders/{order.Id}",
        eventType: "OrderCreated",
        dataVersion: "1.0",
        data: BinaryData.FromObjectAsJson(order)), cancellationToken);

    logger.LogInformation("Accepted order {OrderId} for customer {CustomerId}", order.Id, order.CustomerId);

    return Results.Accepted($"/orders/{order.Id}", new { order.Id, order.Status });
});

app.Run();

static async Task EnsureSqlSchemaAsync(IConfiguration config, CancellationToken cancellationToken)
{
    const string sql = """
    IF OBJECT_ID('dbo.Orders', 'U') IS NULL
    CREATE TABLE dbo.Orders
    (
        Id nvarchar(64) NOT NULL PRIMARY KEY,
        CustomerId nvarchar(128) NOT NULL,
        Sku nvarchar(128) NOT NULL,
        Quantity int NOT NULL,
        Status nvarchar(64) NOT NULL,
        CreatedUtc datetimeoffset NOT NULL
    );
    """;

    await using var connection = new SqlConnection(config["Sql:ConnectionString"]);
    await connection.OpenAsync(cancellationToken);
    await using var command = new SqlCommand(sql, connection);
    await command.ExecuteNonQueryAsync(cancellationToken);
}

static async Task InsertSqlOrderAsync(IConfiguration config, OrderDocument order, CancellationToken cancellationToken)
{
    const string sql = """
    INSERT INTO dbo.Orders (Id, CustomerId, Sku, Quantity, Status, CreatedUtc)
    VALUES (@Id, @CustomerId, @Sku, @Quantity, @Status, @CreatedUtc);
    """;

    await using var connection = new SqlConnection(config["Sql:ConnectionString"]);
    await connection.OpenAsync(cancellationToken);
    await using var command = new SqlCommand(sql, connection);
    command.Parameters.AddWithValue("@Id", order.Id);
    command.Parameters.AddWithValue("@CustomerId", order.CustomerId);
    command.Parameters.AddWithValue("@Sku", order.Sku);
    command.Parameters.AddWithValue("@Quantity", order.Quantity);
    command.Parameters.AddWithValue("@Status", order.Status);
    command.Parameters.AddWithValue("@CreatedUtc", order.CreatedUtc);
    await command.ExecuteNonQueryAsync(cancellationToken);
}

public sealed record CreateOrderRequest(string CustomerId, string Sku, int Quantity);

public sealed record OrderDocument(
    string Id,
    string CustomerId,
    string Sku,
    int Quantity,
    string Status,
    DateTimeOffset CreatedUtc);
