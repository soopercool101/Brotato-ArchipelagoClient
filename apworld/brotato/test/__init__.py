from typing import ClassVar
from .. import BrotatoWorld

from test.bases import WorldTestBase


class BrotatoTestBase(WorldTestBase):
    game = "Brotato"
    world: BrotatoWorld
    player: ClassVar[int] = 1
