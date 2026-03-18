pub(crate) mod common_roles;

pub use common_roles::CommonRolesComponent;

#[cfg(test)]
pub(crate) mod mock_contract;

#[cfg(test)]
mod test;
