using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Azure.Monitor.OpenTelemetry.AspNetCore;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((context, services) =>
    {
        services.AddOpenTelemetry().UseAzureMonitor();
        services.AddSingleton(_ => new ServiceBusClient(
            context.Configuration["ServiceBus:Namespace"],
            new DefaultAzureCredential()));
        services.AddHostedService<OrderWorker>();
    })
    .Build();

await host.RunAsync();

public sealed class OrderWorker(
    ServiceBusClient client,
    IConfiguration configuration,
    ILogger<OrderWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var processor = client.CreateProcessor(configuration["ServiceBus:QueueName"]);

        processor.ProcessMessageAsync += async args =>
        {
            logger.LogInformation(
                "Processing order message {MessageId} with subject {Subject}, correlation {CorrelationId}, delivery {DeliveryCount}",
                args.Message.MessageId,
                args.Message.Subject,
                args.Message.CorrelationId,
                args.Message.DeliveryCount);
            await args.CompleteMessageAsync(args.Message, args.CancellationToken);
        };

        processor.ProcessErrorAsync += args =>
        {
            logger.LogError(args.Exception, "Service Bus processing failed for {EntityPath}", args.EntityPath);
            return Task.CompletedTask;
        };

        await processor.StartProcessingAsync(stoppingToken);

        try
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, stoppingToken);
        }
        catch (OperationCanceledException)
        {
            logger.LogInformation("Order worker shutdown requested.");
        }
        finally
        {
            await processor.StopProcessingAsync(CancellationToken.None);
            await processor.DisposeAsync();
        }
    }
}
