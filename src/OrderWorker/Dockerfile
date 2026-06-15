FROM mcr.microsoft.com/dotnet/runtime:8.0-noble-chiseled@sha256:fa419db60f904e0aa57b455e04a2f6193da69553c38aee35c1f70de48115011b AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:8.0@sha256:7b3124c093e8d7ef44ca965082dfbac6d03d3bde9df8d5be5fb002f06109276a AS build
WORKDIR /src
COPY Directory.Build.props .
COPY src/OrderWorker/OrderWorker.csproj src/OrderWorker/
COPY src/OrderWorker/packages.lock.json src/OrderWorker/
RUN dotnet restore src/OrderWorker/OrderWorker.csproj --locked-mode
COPY src/OrderWorker/ src/OrderWorker/
RUN dotnet publish src/OrderWorker/OrderWorker.csproj --no-restore -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
USER 1654
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "OrderWorker.dll"]
