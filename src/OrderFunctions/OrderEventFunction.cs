using Azure.Messaging.EventGrid;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace OrderFunctions;

public sealed class OrderEventFunction(ILogger<OrderEventFunction> logger)
{
    [Function(nameof(OrderEventFunction))]
    public void Run([EventGridTrigger] EventGridEvent eventGridEvent)
    {
        logger.LogInformation(
            "Received Event Grid event {EventType} for {Subject}.",
            eventGridEvent.EventType,
            eventGridEvent.Subject);
    }
}
