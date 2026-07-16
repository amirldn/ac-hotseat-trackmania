-- Random nickname generator: every player gets a noun from the chosen category,
-- Trackmania hotseat style.

local M = {}

M.categories = {
  {
    name = 'Animals',
    nouns = {
      'Badger', 'Otter', 'Falcon', 'Mongoose', 'Panther', 'Walrus', 'Gecko', 'Ferret',
      'Ocelot', 'Puffin', 'Wombat', 'Iguana', 'Jackal', 'Lemur', 'Marmot', 'Narwhal',
      'Osprey', 'Pelican', 'Quokka', 'Raccoon', 'Stoat', 'Tapir', 'Viper', 'Weasel',
      'Yak', 'Zebra', 'Bison', 'Cougar', 'Dingo', 'Heron', 'Lynx', 'Moose',
    },
  },
  {
    name = 'Fruit & Veg',
    nouns = {
      'Mango', 'Papaya', 'Turnip', 'Kumquat', 'Radish', 'Plum', 'Fig', 'Durian',
      'Parsnip', 'Guava', 'Lychee', 'Quince', 'Rhubarb', 'Apricot', 'Beetroot', 'Celery',
      'Damson', 'Endive', 'Fennel', 'Gherkin', 'Jackfruit', 'Kale', 'Leek', 'Melon',
      'Nectarine', 'Olive', 'Pumpkin', 'Shallot', 'Tomato', 'Yam', 'Sprout', 'Marrow',
    },
  },
  {
    name = 'Space',
    nouns = {
      'Nebula', 'Quasar', 'Pulsar', 'Comet', 'Meteor', 'Nova', 'Eclipse', 'Orbit',
      'Photon', 'Cosmos', 'Zenith', 'Apogee', 'Asteroid', 'Galaxy', 'Neutrino', 'Parsec',
      'Redshift', 'Stardust', 'Corona', 'Magnetar', 'Wormhole', 'Aurora', 'Callisto', 'Europa',
      'Phobos', 'Vega', 'Sputnik', 'Kepler', 'Umbra', 'Perigee', 'Ion', 'Halley',
    },
  },
  {
    name = 'Workshop',
    nouns = {
      'Hammer', 'Wrench', 'Chisel', 'Spanner', 'Pliers', 'Mallet', 'Trowel', 'Anvil',
      'Crowbar', 'Rivet', 'Gasket', 'Sprocket', 'Piston', 'Flange', 'Grommet', 'Winch',
      'Ratchet', 'Swivel', 'Bracket', 'Clamp', 'Dowel', 'Gimlet', 'Hacksaw', 'Jigsaw',
      'Lathe', 'Sander', 'Vice', 'Widget', 'Bolt', 'Pulley', 'Bevel', 'Caliper',
    },
  },
  {
    name = 'Mythical',
    nouns = {
      'Griffin', 'Kraken', 'Phoenix', 'Basilisk', 'Chimera', 'Cyclops', 'Dryad', 'Gorgon',
      'Hydra', 'Kelpie', 'Leviathan', 'Manticore', 'Minotaur', 'Naiad', 'Pegasus', 'Roc',
      'Selkie', 'Siren', 'Sphinx', 'Titan', 'Troll', 'Valkyrie', 'Wyvern', 'Yeti',
      'Djinn', 'Faun', 'Golem', 'Imp', 'Ogre', 'Wraith', 'Banshee', 'Gnome',
    },
  },
}

---Picks `count` unique nouns from a category (1-based index; out-of-range picks a random category).
---@param categoryIndex integer
---@param count integer
---@return string[]
function M.pick(categoryIndex, count)
  local cat = M.categories[categoryIndex] or M.categories[math.random(#M.categories)]
  local pool = {}
  for i = 1, #cat.nouns do pool[i] = cat.nouns[i] end
  for i = #pool, 2, -1 do
    local j = math.random(i)
    pool[i], pool[j] = pool[j], pool[i]
  end
  local out = {}
  for i = 1, count do
    -- More players than nouns: start numbering duplicates.
    out[i] = pool[i] or (pool[(i - 1) % #pool + 1] .. ' ' .. math.ceil(i / #pool))
  end
  return out
end

return M
