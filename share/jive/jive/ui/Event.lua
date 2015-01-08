
--[[
=head1 NAME

jive.ui.Event - An event.

=head1 DESCRIPTION

An event object.

=head1 SYNOPSIS

 -- Create a new event
 local event = jive.ui.Event:new(EVENT_ACTION)
 jive.ui.Framework:pushEvent(event)

 -- Get event properties
 event:getType()
 event:getValue()

=head1 METHODS

=head2 jive.ui.Event:new(type)

I<FIXME make the constructor consistant with loop objects.>

Creates a new Event. I<type> is the event type.

This event can be processed using L<jive.ui.Framework:dispatchEvent> or appended to the event queue using L<jive.ui.Framework:pushEvent>. 

=head2 jive.ui.Event:getType()

Returns the event type.

=head2 jive.ui.Event:getScroll()

Returns the scroll amount for EVENT_SCROLL_* events.

=head2 jive.ui.Event:getKeycode()

Returns the keycode for EVENT_KEY_* events.

=head2 jive.ui.Event:getMouse()

Returns the mouse x,y position for EVENT_MOUSE_* events.

=head2 jive.ui.Event:getAction()

Returns the action name for ACTION events.

=head2 jive.ui.Event:getActionInternal()

Returns the internal representation of the action name for ACTION events. Used by getAction(), should not be needed for general use.

=back


=head1 EVENTS

=over

=head2 EVENT_SCROLL

Scroll event.

=head2 EVENT_ACTION

Action event, sent when a menu item is selected.

=head2 EVENT_KEY_DOWN

A key down event, sent when the key is pressed. Normally the application should use a EVENT_KEY_PRESS or EVENT_KEY_HOLD event.

=head2 EVENT_KEY_UP

A key up event, sent when the key is released. Normally the application should use a EVENT_KEY_PRESS or EVENT_KEY_HOLD event.

=head2 EVENT_KEY_PRESS

A key press event, sent when a key press is detected.

=head2 EVENT_KEY_HOLD

A key hold event, sent when a key hold is detected.

=head2 EVENT_MOUSE_DOWN

A mouse down event, sent when the mouse button is pressed. Normally the application should use a EVENT_MOUSE_PRESS or EVENT_MOUSE_HOLD event.

=head2 EVENT_MOUSE_UP

A mouse down event, sent when the mouse button is released. Normally the application should use a EVENT_MOUSE_PRESS or EVENT_MOUSE_HOLD event.

=head2 EVENT_MOUSE_PRESS

A mouse press event, sent when a mouse button press is detected.

=head2 EVENT_MOUSE_HOLD

A mouse hold event, sent when a mouse button hold is detected.

=head2 EVENT_WINDOW_PUSH

A window push event, sent when a window is pushed on to stage.

=head2 EVENT_WINDOW_POP

A window push event, sent when a window is poped from the stage.

=head2 EVENT_WINDOW_ACTIVE

A window active event, sent when the window is raised to the top of the window stack.

=head2 EVENT_WINDOW_INACTIVE

A window inactive event, sent when the window is no longer at the top of the window stack.

=head2 EVENT_WINDOW_RESIZE

A window resize event, sent whtn the window is resized.

=head2 EVENT_SHOW

A widget show event, sent when the widget is visible.

=head2 EVENT_HIDE

A widget hide event, sent when the widget is no longer visible.

=head2 EVENT_FOCUS_GAINED

A focuse gained event, sent when the widget has gained focus.

=head2 EVENT_FOCUS_LOST

A focuse lost event, sent when the widget has lost focus.

=head2 EVENT_SERVICE_JNT

Used internally.

=head2 EVENT_KEY_ALL

Any EVENT_KEY_* event.

=head2 EVENT_MOUSE_ALL

Any EVENT_MOUSE_* event.

=head2 EVENT_VISIBLE_ALL

Any widget visibility event.

=head2 EVENT_ALL

Any event.

=back


=head1 KEYS

The following keys are used in EVENT_KEY_* events. Multiple key detection is supported. For example you can use I<KEY_PLAY | KEY_PAUSE> to detect when the play and pause keys are both pressed.

=over

=head2 KEY_NONE

=head2 KEY_GO

=head2 KEY_UP

=head2 KEY_DOWN

=head2 KEY_LEFT

=head2 KEY_RIGHT

=head2 KEY_BACK

=head2 KEY_HOME

=head2 KEY_PLAY

=head2 KEY_ADD

=head2 KEY_PAUSE

=head2 KEY_REW

=head2 KEY_FWD

=head2 KEY_VOLUME_UP

=head2 KEY_VOLUME_DOWN

=cut
--]]

local require = require

local oo        = require("loop.base")

module(..., oo.class)

local Framework		= require("jive.ui.Framework")



function getAction(self)
    local actionIndex = self:getActionInternal()
    return Framework:getActionEventNameByIndex(actionIndex)
end


function isIRCode(self, buttonName)
	local irCode = self:getIRCode()
	return (Framework:isIRCode(buttonName, irCode))
end


-- the rest is C implementation

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

