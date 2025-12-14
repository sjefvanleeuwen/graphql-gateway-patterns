FROM mcr.microsoft.com/dotnet/aspnet:10.0-preview AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:10.0-preview AS build
WORKDIR /src
COPY ["NitroSchemaApi/NitroSchemaApi.csproj", "NitroSchemaApi/"]
RUN dotnet restore "NitroSchemaApi/NitroSchemaApi.csproj"
COPY . .
WORKDIR "/src/NitroSchemaApi"
RUN dotnet build "NitroSchemaApi.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "NitroSchemaApi.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "NitroSchemaApi.dll"]
