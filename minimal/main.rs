#![allow(clippy::all)]
#![allow(dead_code)]
#![no_std]
#![no_main]

#[allow(unused_extern_crates)]
extern crate core;

use bsp::entry;
use defmt_rtt as _;
use panic_probe as _;

use rp_pico as bsp;

#[entry]
fn main() -> ! {
    loop {}
}
