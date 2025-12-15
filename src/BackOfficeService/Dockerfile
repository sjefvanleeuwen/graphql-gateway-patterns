FROM mcr.microsoft.com/dotnet/aspnet:10.0-preview AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:10.0-preview AS build
WORKDIR /src
COPY ["BackOfficeService/BackOfficeService.csproj", "BackOfficeService/"]
COPY ["Shared/Shared.csproj", "Shared/"]
RUN dotnet restore "BackOfficeService/BackOfficeService.csproj"
COPY . .
WORKDIR "/src/BackOfficeService"
RUN dotnet build "BackOfficeService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "BackOfficeService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "BackOfficeService.dll"]
