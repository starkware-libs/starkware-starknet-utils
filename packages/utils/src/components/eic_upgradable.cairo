pub mod eic_upgradable;
pub mod interface;

pub use eic_upgradable::EICUpgradableComponent;

#[cfg(test)]
mod mock;
#[cfg(test)]
mod test;
