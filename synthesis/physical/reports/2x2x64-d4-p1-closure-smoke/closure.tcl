set closure_rounds 2
# Re-estimate routed parasitics after legalization before the next repair.
# No clock, load, uncertainty, DRC or endpoint constraint is relaxed.
for {set round 1} {$round <= $closure_rounds} {incr round} {
    foreach kind {electrical hold} {
        puts "Closure round $round: $kind"
        log_cmd global_route -start_incremental
        if {$kind eq "electrical"} {
            repair_design_helper
        } else {
            repair_timing_helper -hold
        }
        detailed_placement_helper -quiet
        log_cmd check_placement -verbose
        log_cmd global_route -end_incremental -congestion_report_file $::env(REPORTS_DIR)/closure_${round}_${kind}.rpt
        log_cmd estimate_parasitics -global_routing
    }
    report_metrics 5 "global route closure round $round"
}
# POST_GLOBAL_ROUTE runs after the stock metrics and guide output. Refresh both
# so reports/guides describe the actual saved checkpoint, not the pre-hook state.
report_metrics 5 "global route after closure"
write_guides $::env(RESULTS_DIR)/route.guide
source [file join $::env(SCRIPTS_DIR) "write_ref_sdc.tcl"]
