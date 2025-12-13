FROM mcr.microsoft.com/dotnet/aspnet:10.0-preview AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:10.0-preview AS build
WORKDIR /src
COPY ["ReviewsService/ReviewsService.csproj", "ReviewsService/"]
COPY ["Shared/Shared.csproj", "Shared/"]
RUN dotnet restore "ReviewsService/ReviewsService.csproj"
COPY . .
WORKDIR "/src/ReviewsService"
RUN dotnet build "ReviewsService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "ReviewsService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "ReviewsService.dll"]
