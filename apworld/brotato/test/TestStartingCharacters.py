from . import BrotatoTestBase
from ..Options import BrotatoOptions, StartingCharacters

from test.general import setup_solo_multiworld


class TestCreateStartingCharacters(BrotatoTestBase):
    def test_default_character_setup_appropriate_options(self):
        world_options = self.world.options_dataclass.type_hints
        option: StartingCharacters
        name, option = next((key, value) for key, value in world_options.items() if value == StartingCharacters)
        self.options[name] = option.option_default_characters
        # breakpoint()
        multiworld = setup_solo_multiworld(self.world, {name: option.option_default_characters})
        assert multiworld
