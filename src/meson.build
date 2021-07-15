cc = meson.get_compiler('c')

sdl_dep = [dependency('sdl'), dependency('SDL_gfx'), dependency('SDL_image'), dependency('SDL_ttf')]
lua_dep = [dependency('lua51'), dependency('lua5.1-bitop'), dependency('luajit'), dependency('lua5.1-filesystem'), dependency('lua5.1-socket'), dependency('lua5.1-cqueues'), dependency('lua5.1-cjson'), dependency('lua5.1-lgi')]
m_dep = cc.find_library('m', required : true)
shm_dep = cc.find_library('rt', required : true)
thread_dep = dependency('threads')

executable('jivelite',
  'common.h',
  'jive.c',
  'jive_debug.c',
  'jive_dns.c',
  'jive_event.c',
  'jive_font.c',
  'jive_framework.c',
  'jive_group.c',
  'jive.h',
  'jive_icon.c',
  'jive_label.c',
  'jive_menu.c',
  'jive_slider.c',
  'jive_style.c',
  'jive_surface.c',
  'jive_textarea.c',
  'jive_textinput.c',
  'jive_utils.c',
  'jive_widget.c',
  'jive_window.c',
  'log.c',
  'log.h',
  'platform_linux.c',
  'resize.c',
  'resource.h',
  'system.c',
  'types.h',
  'version.h',
  'visualizer/kiss_fft.c',
  'visualizer/_kiss_fft_guts.h',
  'visualizer/kiss_fft.h',
  'visualizer/spectrum.c',
  'visualizer/visualizer.c',
  'visualizer/visualizer.h',
  'visualizer/vumeter.c',
  dependencies : [sdl_dep, lua_dep, m_dep, thread_dep, shm_dep],
  install : true)

