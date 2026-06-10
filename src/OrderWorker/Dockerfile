FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/OrderWorker/OrderWorker.csproj src/OrderWorker/
RUN dotnet restore src/OrderWorker/OrderWorker.csproj
COPY . .
RUN dotnet publish src/OrderWorker/OrderWorker.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "OrderWorker.dll"]
