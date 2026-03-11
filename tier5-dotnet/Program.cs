using LoanFinalizer.Data;
using LoanFinalizer.Models;
using LoanFinalizer.Services;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// Add services
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// PostgreSQL Database Context
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection") 
    ?? Environment.GetEnvironmentVariable("DATABASE_URL")
    ?? "Host=localhost;Port=5432;Database=loandb;Username=postgres;Password=postgres";

builder.Services.AddDbContext<LoanDbContext>(options =>
    options.UseNpgsql(connectionString));

builder.Services.AddScoped<LoanCalculationService>();

// Logging
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddJsonConsole();

var app = builder.Build();

// Apply database migrations
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<LoanDbContext>();
    db.Database.Migrate();
}

// Configure Swagger
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

var logger = app.Logger;

app.MapGet("/health", () =>
{
    return Results.Ok(new
    {
        status = "healthy",
        service = "tier5-loan-finalizer",
        timestamp = DateTime.UtcNow
    });
});

app.MapPost("/internal/loan/finalize", async (
    LoanApplication application,
    LoanCalculationService calculationService,
    LoanDbContext dbContext,
    HttpContext httpContext,
    ILogger<Program> logger) =>
{
    var startTime = DateTime.UtcNow;
    var traceparent = httpContext.Request.Headers["traceparent"].FirstOrDefault();
    var tracestate = httpContext.Request.Headers["tracestate"].FirstOrDefault();
    var applicationIdHeader = httpContext.Request.Headers["x-application-id"].FirstOrDefault();

    logger.LogInformation(
        "Tier 5: Received finalization request - applicationId: {ApplicationId}, " +
        "customerId: {CustomerId}, requestedAmount: {RequestedAmount}, " +
        "decisionStatus: {DecisionStatus}, finalScore: {FinalScore}, " +
        "costCenter: {CostCenter}, team: {Team}, environment: {Environment}, " +
        "traceparent: {Traceparent}",
        application.ApplicationId,
        application.CustomerId,
        application.RequestedAmount,
        application.DecisionStatus,
        application.FinalScore,
        application.CostCenter,
        application.Team,
        application.Environment,
        traceparent
    );

    try
    {
        // Calculate approved amount and total due
        calculationService.CalculateLoanAmounts(application);

        // Update timestamp
        application.UpdatedAt = DateTime.UtcNow;

        // Persist to database
        dbContext.LoanApplications.Add(application);
        await dbContext.SaveChangesAsync();

        var latencyMs = (DateTime.UtcNow - startTime).TotalMilliseconds;

        logger.LogInformation(
            "Tier 5: Loan finalized and persisted - applicationId: {ApplicationId}, " +
            "customerId: {CustomerId}, decisionStatus: {DecisionStatus}, " +
            "approvedAmount: {ApprovedAmount}, totalDue: {TotalDue}, " +
            "costCenter: {CostCenter}, team: {Team}, latencyMs: {LatencyMs}, " +
            "traceparent: {Traceparent}",
            application.ApplicationId,
            application.CustomerId,
            application.DecisionStatus,
            application.ApprovedAmount,
            application.TotalDue,
            application.CostCenter,
            application.Team,
            latencyMs,
            traceparent
        );

        return Results.Ok(new
        {
            success = true,
            applicationId = application.ApplicationId,
            decisionStatus = application.DecisionStatus,
            approvedAmount = application.ApprovedAmount,
            totalDue = application.TotalDue,
            decisionReason = application.DecisionReason,
            processingTimeMs = latencyMs
        });
    }
    catch (Exception ex)
    {
        var latencyMs = (DateTime.UtcNow - startTime).TotalMilliseconds;

        logger.LogError(
            ex,
            "Tier 5: Error finalizing loan - applicationId: {ApplicationId}, " +
            "error: {ErrorMessage}, latencyMs: {LatencyMs}, traceparent: {Traceparent}",
            application.ApplicationId,
            ex.Message,
            latencyMs,
            traceparent
        );

        return Results.Problem(
            title: "Error finalizing loan",
            detail: ex.Message,
            statusCode: 500
        );
    }
});

app.MapGet("/internal/loan/{applicationId}", async (
    string applicationId,
    LoanDbContext dbContext,
    ILogger<Program> logger) =>
{
    logger.LogInformation(
        "Tier 5: Retrieving loan application - applicationId: {ApplicationId}",
        applicationId
    );

    var application = await dbContext.LoanApplications
        .FirstOrDefaultAsync(a => a.ApplicationId == applicationId);

    if (application == null)
    {
        logger.LogWarning(
            "Tier 5: Loan application not found - applicationId: {ApplicationId}",
            applicationId
        );
        return Results.NotFound(new { error = "Application not found" });
    }

    return Results.Ok(application);
});

app.MapGet("/internal/loan", async (
    LoanDbContext dbContext,
    string? costCenter,
    string? team,
    string? decisionStatus,
    ILogger<Program> logger) =>
{
    logger.LogInformation(
        "Tier 5: Listing loan applications - costCenter: {CostCenter}, " +
        "team: {Team}, decisionStatus: {DecisionStatus}",
        costCenter, team, decisionStatus
    );

    var query = dbContext.LoanApplications.AsQueryable();

    if (!string.IsNullOrEmpty(costCenter))
        query = query.Where(a => a.CostCenter == costCenter);

    if (!string.IsNullOrEmpty(team))
        query = query.Where(a => a.Team == team);

    if (!string.IsNullOrEmpty(decisionStatus))
        query = query.Where(a => a.DecisionStatus == decisionStatus);

    var applications = await query
        .OrderByDescending(a => a.CreatedAt)
        .Take(100)
        .ToListAsync();

    return Results.Ok(new
    {
        count = applications.Count,
        applications
    });
});

logger.LogInformation("=" + new string('=', 60));
logger.LogInformation("Tier 5 - Loan Finalizer Service Started");
logger.LogInformation("=" + new string('=', 60));
logger.LogInformation("Database: {ConnectionString}", connectionString.Replace(
    connectionString.Contains("Password=") 
        ? connectionString.Substring(connectionString.IndexOf("Password=")) 
        : "", "Password=***"));
logger.LogInformation("Environment: {Environment}", app.Environment.EnvironmentName);
logger.LogInformation("=" + new string('=', 60));

app.Run();
