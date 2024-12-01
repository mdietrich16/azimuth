#![cfg(not(target_os = "none"))]
pub struct SimBackend;

pub trait DroneBackend {
    fn initialize() -> Self;
    fn execute_action(&mut self) -> Result<(), &'static str>;
}

impl DroneBackend for SimBackend {
    fn initialize() -> Self {
        SimBackend
    }

    fn execute_action(&mut self) -> Result<(), &'static str> {
        println!("Simulation: Executing action");
        Ok(())
    }
}
