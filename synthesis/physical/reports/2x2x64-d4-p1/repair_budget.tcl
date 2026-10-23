# Preserve timing constraints; permit hold buffering beyond ORFS's default cap.
rename repair_timing_helper repair_timing_helper_original
proc repair_timing_helper { args } {
    # A cap exception leaves the inserted buffers in the design. A second
    # bounded repair pass can finish using the enlarged design as its budget.
    for {set attempt 0} {$attempt < 3} {incr attempt} {
        if {![catch {repair_timing_helper_original -max_buffer_percent 100 {*}$args} msg opts]} { return }
        if {![string match {*RSZ-0060*} $msg] || $attempt == 2} { return -options $opts $msg }
        puts "Retry hold repair after buffer cap; constraints unchanged"
    }
}
