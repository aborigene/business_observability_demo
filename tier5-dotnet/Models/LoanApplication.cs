using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace LoanFinalizer.Models;

[Table("loan_applications")]
public class LoanApplication
{
    [Key]
    [Column("id")]
    public int Id { get; set; }

    [Required]
    [Column("application_id")]
    [MaxLength(100)]
    public string ApplicationId { get; set; } = string.Empty;

    [Required]
    [Column("customer_id")]
    [MaxLength(100)]
    public string CustomerId { get; set; } = string.Empty;

    [Required]
    [Column("requested_amount")]
    public double RequestedAmount { get; set; }

    [Required]
    [Column("term_months")]
    public int TermMonths { get; set; }

    [Required]
    [Column("product")]
    [MaxLength(100)]
    public string Product { get; set; } = string.Empty;

    [Required]
    [Column("channel")]
    [MaxLength(50)]
    public string Channel { get; set; } = string.Empty;

    [Required]
    [Column("region")]
    [MaxLength(50)]
    public string Region { get; set; } = string.Empty;

    [Required]
    [Column("segment")]
    [MaxLength(50)]
    public string Segment { get; set; } = string.Empty;

    [Required]
    [Column("cost_center")]
    [MaxLength(100)]
    public string CostCenter { get; set; } = string.Empty;

    [Required]
    [Column("team")]
    [MaxLength(100)]
    public string Team { get; set; } = string.Empty;

    [Required]
    [Column("environment")]
    [MaxLength(50)]
    public string Environment { get; set; } = string.Empty;

    [Required]
    [Column("created_at")]
    public DateTime CreatedAt { get; set; }

    [Required]
    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; }

    // Credit scores
    [Column("tier2_score")]
    public int? Tier2Score { get; set; }

    [Column("tier3_score")]
    public int? Tier3Score { get; set; }

    [Column("final_score")]
    public int? FinalScore { get; set; }

    // Decision
    [Column("decision_status")]
    [MaxLength(50)]
    public string? DecisionStatus { get; set; }

    [Column("approved_amount")]
    public double? ApprovedAmount { get; set; }

    [Column("total_due")]
    public double? TotalDue { get; set; }

    [Column("decision_reason")]
    [MaxLength(500)]
    public string? DecisionReason { get; set; }
}
