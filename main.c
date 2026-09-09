#include "app.h"
#include "sl_component_catalog.h"
#include "sl_main_init.h"
#if defined(SL_CATALOG_KERNEL_PRESENT)
#include "sl_main_kernel.h"
#else
#include "sl_main_process_action.h"
#endif
#if defined(SL_CATALOG_POWER_MANAGER_PRESENT)
#include "sl_power_manager.h"
#endif

int main(void) {
#if defined(SL_CATALOG_KERNEL_PRESENT)
    // With a kernel present sl_main wraps main() (-Wl,--wrap=main): first stage
    // init and the scheduler are already running, and this body executes inside
    // the start task. Finish initialisation, then hand over to the application.
    sl_main_second_stage_init();
    app_init();

    while (sl_main_start_task_should_continue()) {
        app_process_action();
    }
#else
    sl_main_init();
    app_init();

    while (1) {
        sl_main_process_action();
        app_process_action();
#if defined(SL_CATALOG_POWER_MANAGER_PRESENT)
        sl_power_manager_sleep();
#endif
    }
#endif
}
