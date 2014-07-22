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

warn = (message) ->
  $('#status').html $('<span>').addClass('warn').html(message)
  console.log 'WARN:', message

info = (message) ->
  $('#status').html $('<span>').addClass('info').html(message)
  console.log 'INFO:', message

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

class ControlPoint
  constructor: (paper, @v) ->
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

  set: (v) ->
    @v = v
    @control.attr 'cx', @v.x
    @control.attr 'cy', @v.y

  remove: () ->
    @control.remove()

  move: (func) ->
    @_on_move = () -> func()

class Lazer
  constructor: (paper, @v1, @v2) ->
    @start = new ControlPoint(paper, @v1)
    @end = new ControlPoint(paper, @v2)
    @line_origin = paper.path([]).attr
      stroke: '#f88'
      strokeWidth: 0.2
    @line = paper.path([]).attr
      stroke: '#88f'
      strokeWidth: 0.5

  remove: () ->
    for obj in [@start, @end, @line, @line_origin]
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
      s = ax2.minus(ax1)
      s = s.dot(1 / s.length())
      s.dot(p.minus(ax1).dot(s) * 2).minus(p).plus(ax1).plus(ax1)

    v0 = @start.v
    v1 = @end.v
    path = ['M', (v0).x, (v0).y]
    hit_count = 0
    while true
      get_t = ((m) -> cross(v0, v1, m.end1.v, m.end2.v))
      min_mirror = min_by_key(get_t, mirrors)
      min_t = get_t(min_mirror)
      mid_point = mid(v0, v1, min_t)
      path.push('L', (mid_point).x, (mid_point).y)
      if min_t > 1 - EPS
        break
      v1 = reflect(v1, min_mirror.end1.v, min_mirror.end2.v)
      v0 = mid_point
      hit_count += 1
      if hit_count > MAX_HIT_COUNT
        warn 'Hit count large than ' + MAX_HIT_COUNT + '. Aborted.'
        break
    @line.attr 'path', path
    @line_origin.attr 'path', ['M', @start.v.x, @start.v.y, 'L', @end.v.x, @end.v.y]
    if hit_count <= MAX_HIT_COUNT
      info 'Finished in ' + hit_count + ' hits.'

class Mirror
  constructor: (paper, v1, v2) ->
    @line = paper.path([]).attr
      stroke: "#000"
      strokeWidth: 1
    @end1 = new ControlPoint(paper, v1)
    @end2 = new ControlPoint(paper, v2)
    @update()

  update: () ->
    v1 = @end1.v
    v2 = @end2.v
    @line.attr 'path', ['M', v1.x, v1.y, 'L', v2.x, v2.y]

  remove: () ->
    for obj in [@end1, @end2, @line]
      obj.remove()

class Manager
  constructor: () ->
    @paper = Raphael('paper', 800, 600)
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
      numbers = $('#input_data').val().trim().replace(/[{}]/g, '').split(/[\ ,]/)
        .map(parseFloat).filter((x) -> not isNaN(x))
    if numbers.length < 4 or numbers.length % 4 != 0
      warn('Invalid data. Data should be more than 4 numbers and multiples of 4.')
      return
    if (1 for x in numbers when isNaN(x)).length != 0
      warn('Data should numbers')
      return
    angle = numbers[2]
    if $('#degree').is(':checked')
      angle *= Math.PI / 180
    distance = numbers[3]
    numbers[2] = end_x = numbers[0] + Math.cos(angle) * distance
    numbers[3] = end_y = numbers[1] + Math.sin(angle) * distance
    # Adjust
    numbers = @adjust_numbers(numbers)
    # Create
    @lazer = @build_lazer(numbers.slice(0, 4)...)
    @mirrors = for i in [4..numbers.length-1] by 4
      @build_mirror(numbers.slice(i, i + 4)...)

    # Bind the update functions
    update = () =>
      @lazer.update(@mirrors)
    @lazer.start.move update
    @lazer.end.move update

    for mirror in @mirrors
      update = ((mirror) => () =>
        mirror.update()
        @lazer.update(@mirrors)
      )(mirror)
      mirror.end1.move update
      mirror.end2.move update

    @lazer.update(@mirrors)
    info 'Done'

  adjust_numbers: (a) ->
    if not $('#end_visible').is(':checked')
      end_x = a[2]
      end_y = a[3]
      a[2] = a[0]
      a[3] = a[1]
    xs = (a[i] for i in [0..a.length-1] by 2)
    ys = (a[i] for i in [1..a.length-1] by 2)
    x0 = Math.min(xs...)
    x1 = Math.max(xs...)
    y0 = Math.min(ys...)
    y1 = Math.max(ys...)
    if not $('#end_visible').is(':checked')
      a[2] = end_x
      a[3] = end_y
    scale = Math.min(@paper.width / (x1 - x0), @paper.height / (y1 - y0)) / 1.2
    xc = (x1 + x0) / 2
    yc = (y1 + y0) / 2
    if not isFinite(scale)
      scale = 1
      xc = @paper.width / 2
      yc = @paper.height / 2
    convert_x = (x) => (x - xc) * scale + @paper.width / 2
    convert_y = (y) => (y - yc) * scale + @paper.height / 2
    result = []
    for i in [0..a.length - 1] by 2
      result.push(convert_x(a[i]), convert_y(a[i + 1]))
    return result

  build_lazer: (x1, y1, x2, y2) ->
    lazer = new Lazer(@paper, new Vec2(x1, y1), new Vec2(x2, y2))

  build_mirror: (x1, y1, x2, y2) ->
    new Mirror(@paper, new Vec2(x1, y1), new Vec2(x2, y2))

$ () ->
  manager = new Manager()
