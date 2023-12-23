pub mod client;
mod to_variant;
use archipelago_rs::client::{
    ArchipelagoClient, ArchipelagoClientReceiver, ArchipelagoClientSender, ArchipelagoError,
};
use archipelago_rs::protocol::{ClientMessage, Connect, NetworkVersion, RoomInfo, ServerMessage};
use futures::executor;
use gdnative::prelude::*;
use tokio::runtime::{Builder, Runtime};
use tokio::task::LocalSet;

fn init(handle: InitHandle) {
    gdnative::tasks::register_runtime(&handle);
    gdnative::tasks::set_executor(EXECUTOR.with(|e| *e));
    handle.add_class::<GodotArchipelagoClient>();
    handle.add_class::<AsyncExecutorDriver>();
}

godot_init!(init);

thread_local! {
    static EXECUTOR: &'static SharedLocalPool = {
        Box::leak(Box::new(SharedLocalPool::default()))
    };
}

#[derive(NativeClass)]
#[no_constructor]
#[inherit(Node)]
pub struct GodotArchipelagoClient {
    url: String,
    sender: ArchipelagoClientSender,
    receiver: ArchipelagoClientReceiver,
}

impl GodotArchipelagoClient {
    // fn new(_base: &Node) -> Self {
    //     GodotArchipelagoClient { client: None }
    // }
}

// #[derive(NativeClass)]
// #[no_constructor]
// #[inherit(Object)]
// pub struct

// #[derive(NativeClass)]
// #[no_constructor]
// #[inherit(Object)]
// pub struct ConnectResult(Connected);

// impl ToVariant for ConnectResult {
//     fn to_variant(&self) -> Variant {
//         let dict = Dictionary::new_shared();
//         let player_names = self.0.players.into_iter().map(|p| p.name).collect();
//         dict.update("team", self.0.team);
//         dict.update("slot", self.0.slot);
//         dict.update("players", player_names);
//         dict.update("missing_locations", self.0.missing_locations);
//         dict.update("checked_locations", self.0.checked_locations);
//         dict.update("slot_info", self.0.slot_info);
//         dict.to_variant()
//     }
// }

pub enum GdArchipelagoError {
    IllegalResponse {
        received: ServerMessage,
        expected: &'static str,
    },
    ConnectionClosed,
    FailedSerialize,
    NonTextWebsocketResult,
    NetworkError,
}

impl GdArchipelagoError {
    fn from_ap_error(err: ArchipelagoError) -> Self {
        match err {
            ArchipelagoError::IllegalResponse { received, expected } => {
                GdArchipelagoError::IllegalResponse {
                    received,
                    expected: &expected,
                }
            }
            ArchipelagoError::ConnectionClosed => GdArchipelagoError::ConnectionClosed,
            ArchipelagoError::FailedSerialize(_) => GdArchipelagoError::FailedSerialize,
            ArchipelagoError::NetworkError(_) => GdArchipelagoError::NetworkError,
            ArchipelagoError::NonTextWebsocketResult(_) => {
                GdArchipelagoError::NonTextWebsocketResult
            }
        }
    }
}

impl ToVariant for GdArchipelagoError {
    fn to_variant(&self) -> Variant {
        match self {
            GdArchipelagoError::IllegalResponse { received, expected } => format!(
                "Illegal response, expected {}, received {}",
                expected,
                serde_json::to_string(received).unwrap()
            )
            .to_variant(),
            GdArchipelagoError::ConnectionClosed => "connection closed by server".to_variant(),
            GdArchipelagoError::FailedSerialize => "data failed to serialze".to_variant(),
            GdArchipelagoError::NonTextWebsocketResult => {
                "unexpected non-text result form websocket".to_variant()
            }
            GdArchipelagoError::NetworkError => "network error".to_variant(),
        }
    }
}

// impl ToVariant<T where T: ToVariant> for Future<T> {
//     fn to_variant(&self) -> Variant {
//         0.to_variant()
//     }
// }

#[methods]
impl GodotArchipelagoClient {
    #[method]
    pub fn send_connect(
        &mut self,
        game: String,
        name: String,
        password: Option<String>,
        items_handling: Option<i32>,
        tags: Vec<String>,
    ) -> Result<(), GdArchipelagoError> {
        let message = ClientMessage::Connect(Connect {
            game,
            name,
            password,
            items_handling,
            tags,
            uuid: "".to_string(),
            version: NetworkVersion {
                major: 0,
                minor: 4,
                build: 4,
                class: "Version".to_string(),
            },
        });
        let result = executor::block_on(self.sender.send(message));
        match result {
            Ok(_) => Ok(()),
            Err(err) => Err(GdArchipelagoError::from_ap_error(err)),
        }
    }

    #[method]
    pub fn room_info(&self) -> RoomInfo {
        *self.receiver.room_info()
    }
}

impl ToVariant for GodotArchipelagoClient {
    fn to_variant(&self) -> Variant {
        self.url.to_variant()
    }
}

#[derive(NativeClass, ToVariant, FromVariant)]
#[no_constructor]
#[inherit(Node)]
struct GodotArchipelagoClientFactory {}

impl GodotArchipelagoClientFactory {
    // fn new(_base: &Node) -> Self {
    //     GodotArchipelagoClientFactory {}
    // }
}

#[methods]
impl GodotArchipelagoClientFactory {
    #[method]
    fn create_client(&self, url: String) -> Option<GodotArchipelagoClient> {
        let client = executor::block_on(ArchipelagoClient::new(url.as_str())).ok();
        match client {
            Some(client) => Some({
                let (sender, receiver) = client.split();
                GodotArchipelagoClient {
                    url,
                    sender,
                    receiver,
                }
            }),
            None => None,
        }
    }
}

#[derive(NativeClass, Clone, Copy, Default)]
#[no_constructor]
#[inherit(Object)]
struct ClientCache;

#[derive(Default)]
struct SharedLocalPool {
    local_set: LocalSet,
}

impl futures::task::LocalSpawn for SharedLocalPool {
    fn spawn_local_obj(
        &self,
        future: futures::task::LocalFutureObj<'static, ()>,
    ) -> Result<(), futures::task::SpawnError> {
        self.local_set.spawn_local(future);
        Ok(())
    }
}

#[derive(NativeClass)]
#[inherit(Node)]
struct AsyncExecutorDriver {
    runtime: Runtime,
}

impl AsyncExecutorDriver {
    fn new(_base: &Node) -> Self {
        AsyncExecutorDriver {
            runtime: Builder::new_current_thread()
                .enable_io() // optional, depending on your needs
                .build()
                .unwrap(),
        }
    }
}

#[methods]
impl AsyncExecutorDriver {
    #[method]
    fn _process(&self, #[base] _base: &Node, _delta: f64) {
        EXECUTOR.with(|e| {
            self.runtime
                .block_on(async {
                    e.local_set
                        .run_until(async { tokio::task::spawn_local(async {}).await })
                        .await
                })
                .unwrap()
        })
    }
}
