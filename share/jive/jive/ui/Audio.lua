

--[[
=head1 NAME

jive.ui.Audio - Audio effects and playback

=head1 DESCRIPTION

An class for audio effects and playback.

=head1 SYNOPSIS

 -- Load wav file in channel 1
 local wav = jive.ui.Audio:loadSound(filename, 1)

 -- Play sound
 wav:play()

=head1 METHODS

=head2 jive.ui.Audio:loadSound(file, mixer)

=head2 jive.ui.Audio:effectsEnable(enable)

=head2 jive.ui.Audio:isEffectsEnabled()

=head1 jive.ui.Sound METHODS

=head2 jive.ui.Audio:play()

=head2 jive.ui.Audio:enable(enable)

=head2 jive.ui.Audio:isEnabled()


=cut
--]]


local oo            = require("loop.simple")

module(..., oo.class)


-- C implementation

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

