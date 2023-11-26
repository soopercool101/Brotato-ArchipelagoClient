from typing import ClassVar
from .. import BrotatoWorld

from test.TestBase import WorldTestBase


class BrotatoTestBase(WorldTestBase):
    game = "Brotato"
    world: BrotatoWorld
    player: ClassVar[int] = 1

    def world_setup(self, seed: int | None = None) -> None:
        super().world_setup(seed=seed)
        if self.constructed:
            self.world = self.multiworld.worlds[self.player]
