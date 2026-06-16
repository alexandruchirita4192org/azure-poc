FROM mcr.microsoft.com/dotnet/runtime:10.0-noble-chiseled@sha256:03c2c32d689e9379d0902ba52434c1e76ce2950f2cf04f19cacb0147842e70d1 AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:46a703da08438d0b2cf11a1898ed81b9fc28c83787b25e5220dc47c43bb90aa3 AS build
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
