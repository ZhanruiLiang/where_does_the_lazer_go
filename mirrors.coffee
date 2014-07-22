'use strict'

min_by_key = (key, xs) ->
  best = null
  best_key = null
  for x in xs
    x_key = key(x)
    if best == null or x_key < best_key
      best = x
      best_key = x_key
  return best


class Vec2
  constructor: (@x, @y) ->

  dot: (v) ->
    if v instanceof Vec2
      @x * v.x + @y * v.y
    else
      new Vec2(@x * v, @y * v)

  cross: (v) ->
      @x * v.y - @y * v.x

  minus: (v) ->
    new Vec2(@x - v.x, @y - v.y)

  plus: (v) ->
    new Vec2(@x + v.x, @y + v.y)

  length: () ->
    Math.sqrt(@x * @x + @y * @y)

class Viewer
  constructor: (@paper) ->
    @controls = []
    @update()

  update: () ->
    if @controls.length < 2
      @scale = 1
      @center = new Vec2(0, 0)
    else
      min_x = Math.min((c.v.x for c in @controls)...)
      max_x = Math.max((c.v.x for c in @controls)...)
      min_y = Math.min((c.v.y for c in @controls)...)
      max_y = Math.max((c.v.y for c in @controls)...)
      @scale = Math.min(@paper.width / (max_x - min_x), @paper.height / (max_y - min_y)) / 1.2
      @center = new Vec2((min_x + min_x) / 2, (min_y + max_y) / 2)
    console.log 'Viewer:', @scale, @center
    for control in @controls
      control.sync_from_value()

  to_screen: (p) ->
    return (new Vec2(@paper.width / 2, @paper.height / 2)).plus(p.minus(@center).dot(@scale))

  add: (control) ->
    @controls.push(control)

  remove: (control) ->
    @controls.pop(@controls.indexOf(control))


class ControlPoint
  constructor: (paper, @viewer, @v) ->
    start = (x, y, e) =>
      @_x0 = @v.x
      @_y0 = @v.y

    end = (x, y, e) =>
      delete @_x0
      delete @_y0

    move = (dx, dy, x, y, e) =>
      @set new Vec2(@_x0 + dx, @_y0 + dy)
      if @_on_move?
        @_on_move()

    @control = paper.circle(@v.x, @v.y, 3)
      .attr
        stroke: "#000"
        strokeWidth: 1
        fill: "#fff"
      .drag move, start, end
    @_on_move = null
    @viewer.add(this)

  set: (v) ->
    @v = v
    @sync_from_value()

  sync_from_value: () ->
    screen_pos = @viewer.to_screen(@v)
    @control.attr 'cx', screen_pos.x
    @control.attr 'cy', screen_pos.y

  remove: () ->
    @control.remove()

  move: (func) ->
    @_on_move = () -> func()

class Lazer
  constructor: (paper, @viewer, @v1, @v2) ->
    @start = new ControlPoint(paper, viewer, @v1)
    @end = new ControlPoint(paper, viewer, @v2)
    @line = paper.path([]).attr
      stroke: '#88f'
      strokeWidth: 0.5

  remove: () ->
    for obj in [@start, @end, @line]
      obj.remove()

  update: (mirrors) ->
    EPS = 1e-6
    MAX_HIT_COUNT = 100000
    cross = (v1, v2, v3, v4) ->
      # 0 < t1 < 1
      # 0 <= t2 <= 1
      # return t1 or 1
      d0 = v2.minus(v1).cross(v3.minus(v4))
      if Math.abs(d0) < EPS
        return 1
      t1 = v3.minus(v1).cross(v3.minus(v4)) / d0
      t2 = v2.minus(v1).cross(v3.minus(v1)) / d0
      if EPS < t1 < 1 - EPS and -EPS < t2 < 1 + EPS
        return t1
      return 1

    mid = (v1, v2, t) ->
      new Vec2(v1.x * (1 - t) + v2.x * t, v1.y * (1 - t) + v2.y * t)

    reflect = (p, ax1, ax2) ->
      s = ax1.minus(ax2)
      s = s.dot(1 / s.length())
      s.dot(p.minus(ax1).dot(s) * 2).minus(p)

    v0 = @start.v
    v1 = @end.v
    path = ['M', @viewer.to_screen(v0).x, @viewer.to_screen(v0).y]
    hit_count = 0
    while true
      get_t = ((m) -> cross(v0, v1, m.end1.v, m.end2.v))
      min_mirror = min_by_key(get_t, mirrors)
      min_t = get_t(min_mirror)
      mid_point = mid(v0, v1, min_t)
      path.push('L', @viewer.to_screen(mid_point).x, @viewer.to_screen(mid_point).y)
      if min_t > 1 - EPS
        break
      v1 = reflect(v1, min_mirror.end1.v, min_mirror.end2.v)
      v0 = mid_point
      hit_count += 1
      if hit_count > MAX_HIT_COUNT
        warn 'Hit count large than ' + MAX_HIT_COUNT + '. Aborted.'
        break
    @end.set(v1)
    @line.attr 'path', path
    @viewer.update()
    if hit_count <= MAX_HIT_COUNT
      console.log 'Finished in ' + hit_count + ' hits.'
    console.log path

class Mirror
  constructor: (paper, @viewer, v1, v2) ->
    @line = paper.path([]).attr
      stroke: "#000"
      strokeWidth: 1
    @end1 = new ControlPoint(paper, viewer, v1)
    @end2 = new ControlPoint(paper, viewer, v2)
    @update()

  update: () ->
    v1 = @viewer.to_screen(@end1.v)
    v2 = @viewer.to_screen(@end2.v)
    @line.attr 'path', ['M', v1.x, v1.y, 'L', v2.x, v2.y]

  remove: () ->
    for obj in [@end1, @end2, @line]
      obj.remove()

class Manager
  constructor: () ->
    @paper = Raphael('paper', 800, 600)
    @viewer = new Viewer(@paper)
    @lazer = null
    @mirrors = []

    $('#btn_update').click () =>
      @reload_input()

    $('#btn_reset').click () =>
      @reset()

    info 'Input data and then press "Update"'

  reset: () ->
    $('#input_data').val('')
    @clear()

  clear: () ->
    if @lazer
      @lazer.remove()
    @lazer = null
    for mirror in @mirrors
      mirror.remove()
    @mirrors = []

  reload_input: () ->
    @clear()
    
    format = $('#format').val()
    if format == 'plain'
      numbers = $('#input_data').val().trim().split(/\ +/).map parseFloat
    else if format == 'MMA'
      numbers = $('#input_data').val().trim().replace(/[{}]/g, '').map parseFloat
    if numbers.length < 4 or numbers.length % 4 != 0
      warn('Invalid data. Data should be more than 4 numbers and multiples of 4.')
      return
    if (1 for x in numbers when isNaN(x)).length != 0
      warn('Data should numbers')
      return
    @lazer = @build_lazer(numbers.slice(0, 4)...)
    @mirrors = for i in [4..numbers.length-1] by 4
      @build_mirror(numbers.slice(i, i + 4)...)

    # Bind the update functions
    update = () =>
      @viewer.update()
      @lazer.update(@mirrors)
    @lazer.start.move update
    @lazer.end.move update

    for mirror in @mirrors
      update = ((mirror) => () =>
        mirror.update()
        @viewer.update()
        @lazer.update(@mirrors)
      )(mirror)
      mirror.end1.move update
      mirror.end2.move update

    @viewer.update()
    @lazer.update(@mirrors)
    info 'Done'

  build_lazer: (x1, y1, angle, distance) ->
    if $('#degree').is(':checked')
      angle *= Math.PI / 180
    lazer = new Lazer(@paper, @viewer,
      new Vec2(x1, y1),
      new Vec2(x1 + Math.cos(angle) * distance, y1 + Math.sin(angle) * distance),
    )

  build_mirror: (x1, y1, x2, y2) ->
    new Mirror(@paper, @viewer, new Vec2(x1, y1), new Vec2(x2, y2))

$ () ->
  manager = new Manager()

warn = (message) ->
  $('#status').html $('<span>').addClass('warn').html(message)
  console.log 'WARN:', message

info = (message) ->
  $('#status').html $('<span>').addClass('info').html(message)
  console.log 'INFO:', message

