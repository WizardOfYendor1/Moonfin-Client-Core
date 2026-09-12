/// TMDB image bases for the artwork Seerr hands back as bare paths. The widths
/// are picked per slot, so a poster never downloads at backdrop size.
const seerrPosterBase = 'https://image.tmdb.org/t/p/w342';
const seerrBackdropBase = 'https://image.tmdb.org/t/p/w1280';
const seerrProfileBase = 'https://image.tmdb.org/t/p/w185';

/// Portrait size for slots that show a person at card size (200 to 355px
/// wide), where w185 would upscale.
const seerrProfileLargeBase = 'https://image.tmdb.org/t/p/w500';
