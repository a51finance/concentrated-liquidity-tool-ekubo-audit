#[derive(Copy, Drop, Serde)]
pub enum CallbackMethod {
    Add,
    Collect,
    Remove,
    Remove_and_save,
    Load_and_Remove,
}
