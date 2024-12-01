#![no_std]

use bsp::hal::{
    clocks::{init_clocks_and_plls, Clock},
    pac,
    sio::Sio,
    watchdog::Watchdog,
};
use rp_pico as bsp;

use defmt::*;
use defmt_rtt as _;
use panic_probe as _;

pub struct HwBackend {
    // led_pin: bsp::hal::gpio::Pin<, //<bsp::hal::gpio::bank0::Gpio25, bsp::hal::gpio::PushPullOutput>,
    led_pin: bsp::hal::gpio::Pin<
        bsp::hal::gpio::bank0::Gpio25,
        bsp::hal::gpio::FunctionSio<bsp::hal::gpio::SioOutput>,
        <bsp::hal::gpio::bank0::Gpio25 as bsp::hal::gpio::DefaultTypeState>::PullType,
    >,
    delay: cortex_m::delay::Delay,
}

pub trait DroneBackend {
    fn initialize() -> Self;
    fn execute_action(&mut self) -> Result<(), &'static str>;
}

impl DroneBackend for HwBackend {
    fn initialize() -> Self {
        let mut pac = pac::Peripherals::take().unwrap();
        let core = pac::CorePeripherals::take().unwrap();
        let mut watchdog = Watchdog::new(pac.WATCHDOG);
        let sio = Sio::new(pac.SIO);

        let external_xtal_freq_hz = 12_000_000u32;
        let clocks = init_clocks_and_plls(
            external_xtal_freq_hz,
            pac.XOSC,
            pac.CLOCKS,
            pac.PLL_SYS,
            pac.PLL_USB,
            &mut pac.RESETS,
            &mut watchdog,
        )
        .ok()
        .unwrap();

        let delay = cortex_m::delay::Delay::new(core.SYST, clocks.system_clock.freq().to_Hz());

        let pins = bsp::Pins::new(
            pac.IO_BANK0,
            pac.PADS_BANK0,
            sio.gpio_bank0,
            &mut pac.RESETS,
        );

        HwBackend {
            led_pin: pins.led.into_push_pull_output(),
            delay,
        }
    }

    fn execute_action(&mut self) -> Result<(), &'static str> {
        use embedded_hal::digital::OutputPin;

        self.led_pin.set_high().map_err(|_| "Failed to set LED")?;
        self.delay.delay_ms(200);
        self.led_pin.set_low().map_err(|_| "Failed to clear LED")?;
        self.delay.delay_ms(500);
        Ok(())
    }
}
