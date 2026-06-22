using Azure.Messaging.EventGrid;
using Microsoft.Extensions.Logging;
using Xunit;

namespace OrderFunctions.Tests;

public sealed class OrderEventFunctionTests
{
    [Fact]
    public void Run_logs_event_type_and_subject()
    {
        var logger = new TestLogger<OrderFunctions.OrderEventFunction>();
        var function = new OrderFunctions.OrderEventFunction(logger);
        var eventGridEvent = new EventGridEvent(
            subject: "orders/123",
            eventType: "OrderCreated",
            dataVersion: "1.0",
            data: BinaryData.FromString("""{"orderId":"123"}"""));

        function.Run(eventGridEvent);

        Assert.Single(logger.Entries);
        Assert.Equal(LogLevel.Information, logger.Entries[0].Level);
        Assert.Equal("Received Event Grid event OrderCreated for orders/123.", logger.Entries[0].Message);
    }

    private sealed class TestLogger<T> : ILogger<T>
    {
        public List<TestLogEntry> Entries { get; } = [];

        public IDisposable BeginScope<TState>(TState state) where TState : notnull
            => NullScope.Instance;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            Entries.Add(new TestLogEntry(logLevel, formatter(state, exception)));
        }
    }

    private sealed record TestLogEntry(LogLevel Level, string Message);

    private sealed class NullScope : IDisposable
    {
        public static readonly NullScope Instance = new();

        public void Dispose()
        {
        }
    }
}
