using LoanFinalizer.Models;
using Microsoft.EntityFrameworkCore;

namespace LoanFinalizer.Data;

public class LoanDbContext : DbContext
{
    public LoanDbContext(DbContextOptions<LoanDbContext> options) : base(options)
    {
    }

    public DbSet<LoanApplication> LoanApplications { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Additional indexes for performance
        modelBuilder.Entity<LoanApplication>()
            .HasIndex(a => a.ApplicationId)
            .IsUnique();

        modelBuilder.Entity<LoanApplication>()
            .HasIndex(a => a.CustomerId);

        modelBuilder.Entity<LoanApplication>()
            .HasIndex(a => a.CostCenter);

        modelBuilder.Entity<LoanApplication>()
            .HasIndex(a => a.Team);

        modelBuilder.Entity<LoanApplication>()
            .HasIndex(a => a.DecisionStatus);

        modelBuilder.Entity<LoanApplication>()
            .HasIndex(a => a.CreatedAt);
    }
}
