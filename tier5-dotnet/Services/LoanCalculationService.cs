using LoanFinalizer.Models;

namespace LoanFinalizer.Services;

public class LoanCalculationService
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<LoanCalculationService> _logger;

    public LoanCalculationService(IConfiguration configuration, ILogger<LoanCalculationService> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public void CalculateLoanAmounts(LoanApplication application)
    {
        var finalScore = application.FinalScore ?? 0;
        var requestedAmount = application.RequestedAmount;
        var termMonths = application.TermMonths;
        var decisionStatus = application.DecisionStatus ?? "UNKNOWN";

        _logger.LogInformation(
            "Calculating loan amounts - applicationId: {ApplicationId}, " +
            "requestedAmount: {RequestedAmount}, finalScore: {FinalScore}, " +
            "decisionStatus: {DecisionStatus}",
            application.ApplicationId,
            requestedAmount,
            finalScore,
            decisionStatus
        );

        // Calculate approved amount based on decision status
        double approvedAmount = decisionStatus switch
        {
            "APPROVED" => requestedAmount,
            "REJECTED" => 0,
            "PARTIALLY_APPROVED" => CalculatePartialApproval(requestedAmount, finalScore),
            _ => 0
        };

        // Ensure approved amount is never negative
        approvedAmount = Math.Max(0, approvedAmount);

        // Calculate total due (with interest)
        double totalDue = CalculateTotalDue(approvedAmount, finalScore, termMonths);

        application.ApprovedAmount = approvedAmount;
        application.TotalDue = totalDue;

        _logger.LogInformation(
            "Loan amounts calculated - applicationId: {ApplicationId}, " +
            "approvedAmount: {ApprovedAmount}, totalDue: {TotalDue}",
            application.ApplicationId,
            approvedAmount,
            totalDue
        );
    }

    private double CalculatePartialApproval(double requestedAmount, int finalScore)
    {
        // Partial approval formula: requestedAmount - (100 - finalScore)
        // The lower the score, the higher the reduction
        var reduction = 100 - finalScore;
        var partialAmount = requestedAmount - reduction;

        _logger.LogDebug(
            "Calculating partial approval - requestedAmount: {RequestedAmount}, " +
            "finalScore: {FinalScore}, reduction: {Reduction}, result: {Result}",
            requestedAmount,
            finalScore,
            reduction,
            partialAmount
        );

        return Math.Max(0, partialAmount);
    }

    private double CalculateTotalDue(double approvedAmount, int finalScore, int termMonths)
    {
        if (approvedAmount <= 0)
        {
            return 0;
        }

        // Get base rate from configuration (default: 0.02 = 2% per month)
        var baseRate = _configuration.GetValue<double>("Loan:BaseRate", 0.02);

        // Calculate risk premium based on score
        // Lower score = higher risk premium
        // Formula: (100 - finalScore) / 1000
        // Examples:
        //   - finalScore = 90 → riskPremium = 0.010 (1.0%)
        //   - finalScore = 50 → riskPremium = 0.050 (5.0%)
        //   - finalScore = 20 → riskPremium = 0.080 (8.0%)
        var riskPremium = (100.0 - finalScore) / 1000.0;

        // Total interest rate per month
        var interestRate = baseRate + riskPremium;

        // Total due = approvedAmount * (1 + interestRate * termMonths)
        // This is simple interest for demonstration purposes
        var totalDue = approvedAmount * (1 + interestRate * termMonths);

        _logger.LogDebug(
            "Calculating total due - approvedAmount: {ApprovedAmount}, " +
            "finalScore: {FinalScore}, termMonths: {TermMonths}, " +
            "baseRate: {BaseRate}, riskPremium: {RiskPremium}, " +
            "interestRate: {InterestRate}, totalDue: {TotalDue}",
            approvedAmount,
            finalScore,
            termMonths,
            baseRate,
            riskPremium,
            interestRate,
            totalDue
        );

        return Math.Round(totalDue, 2);
    }
}
