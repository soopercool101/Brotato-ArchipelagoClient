use archipelago_rs::client::{ArchipelagoClient, ArchipelagoError};
use archipelago_rs::protocol::Connected;
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
    client: ArchipelagoClient,
}

impl GodotArchipelagoClient {
    // fn new(_base: &Node) -> Self {
    //     GodotArchipelagoClient { client: None }
    // }
}

#[methods]
impl GodotArchipelagoClient {
    #[method]
    pub async fn connect(
        &mut self,
        game: String,
        name: String,
        password: Option<String>,
        items_handling: Option<i32>,
        tags: Vec<String>,
    ) -> Result<Connected, ArchipelagoError> {
        let password = password.or("".to_owned());
        let password = match password {
            Some(pw) => Some(pw.as_str()),
            None => None,
        };
        self.client
            .connect(game.as_str(), name.as_str(), password, items_handling, tags)
            .await
    }
}

#[derive(NativeClass)]
#[inherit(Reference)]
struct GodotArchipelagoClientFactory {}

impl GodotArchipelagoClientFactory {
    fn new(_base: &Node) -> Self {
        GodotArchipelagoClientFactory {}
    }
}

#[methods]
impl GodotArchipelagoClientFactory {
    #[method]
    async fn create_client(&self, url: String) -> Option<Instance<GodotArchipelagoClient, Unique>> {
        let client = ArchipelagoClient::new(url.as_str()).await.ok();
        match client {
            Some(client) => Some(GodotArchipelagoClient { client }.emplace()),
            None => None,
        }
    }
}

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
