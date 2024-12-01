#![cfg_attr(target_os = "none", no_std)]
#![cfg_attr(target_os = "none", no_main)]

#[cfg(target_os = "none")]
use azimuth_hal_pico::{DroneBackend, HwBackend};

#[cfg(not(target_os = "none"))]
use azimuth_hal_sim::{DroneBackend, SimBackend};

#[cfg_attr(target_os = "none", cortex_m_rt::entry)]
fn main() -> ! {
    #[cfg(target_os = "none")]
    let mut backend = HwBackend::initialize();

    #[cfg(not(target_os = "none"))]
    let mut backend = SimBackend::initialize();

    loop {
        backend.execute_action().expect("Failed to execute action");
    }
}
