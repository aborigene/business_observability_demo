FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
WORKDIR /src

COPY *.csproj .
# Cache NuGet packages across builds — avoids re-downloading on every rebuild
RUN --mount=type=cache,target=/root/.nuget/packages dotnet restore --verbosity detailed

COPY . .
RUN --mount=type=cache,target=/root/.nuget/packages dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine
WORKDIR /app

COPY --from=build /app/publish .

RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 5000

ENV ASPNETCORE_URLS=http://+:5000

ENTRYPOINT ["dotnet", "LoanFinalizer.dll"]
