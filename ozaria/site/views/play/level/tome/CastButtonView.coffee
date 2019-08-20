require('ozaria/site/styles/play/level/tome/cast_button.sass')
CocoView = require 'views/core/CocoView'
template = require 'ozaria/site/templates/play/level/tome/cast-button-view'
{me} = require 'core/auth'
LadderSubmissionView = require 'views/play/common/LadderSubmissionView'
LevelSession = require 'models/LevelSession'
async = require('vendor/scripts/async.js')
GoalManager = require('lib/world/GoalManager')

module.exports = class CastButtonView extends CocoView
  id: 'cast-button-view'
  template: template

  events:
    'click #run': 'onRunButtonClick'
    'click #update-game': 'onUpdateButtonClick'
    'click #next': 'onNextButtonClick'

  subscriptions:
    'tome:spell-changed': 'onSpellChanged'
    'tome:cast-spells': 'onCastSpells'
    'tome:manual-cast-denied': 'onManualCastDenied'
    'god:new-world-created': 'onNewWorld'
    'goal-manager:new-goal-states': 'onNewGoalStates'
    'god:goals-calculated': 'onGoalsCalculated'
    'playback:ended-changed': 'onPlaybackEndedChanged'
    'playback:playback-ended': 'onPlaybackEnded'

  constructor: (options) ->
    super options
    @spells = options.spells
    @castShortcut = '⇧↵'
    @updateReplayabilityInterval = setInterval @updateReplayability, 1000
    @observing = options.session.get('creator') isnt me.id
    # WARNING: CourseVictoryModal does not handle mirror sessions when submitting to ladder; adjust logic if a
    # mirror level is added to
    # Keep server/middleware/levels.coffee mirror list in sync with this one
    @loadMirrorSession() if @options.level.get('mirrorMatch') or @options.level.get('slug') in ['ace-of-coders', 'elemental-wars', 'the-battle-of-sky-span', 'tesla-tesoro', 'escort-duty', 'treasure-games', 'king-of-the-hill']  # TODO: remove slug list once these levels are configured as mirror matches
    @mirror = @mirrorSession?
    @autoSubmitsToLadder = @options.level.isType('course-ladder')
    # Show publish CourseVictoryModal if they've already published
    if options.session.get('published')
      Backbone.Mediator.publish 'level:show-victory', { showModal: true, manual: false }

  destroy: ->
    clearInterval @updateReplayabilityInterval
    super()

  afterRender: ->
    super()
    @castButton = $('.cast-button', @$el)
    spell.view?.createOnCodeChangeHandlers() for spellKey, spell of @spells
    if @options.level.get('hidesSubmitUntilRun') or @options.level.get('hidesRealTimePlayback') or @options.level.isType('web-dev')
      @$el.find('.submit-button').hide()  # Hide Submit for the first few until they run it once.
    if @options.session.get('state')?.complete and (@options.level.get('hidesRealTimePlayback') or @options.level.isType('web-dev'))
      @$el.find('.done-button').show()
    if @options.level.get('slug') in ['course-thornbush-farm', 'thornbush-farm']
      @$el.find('.submit-button').hide()  # Hide submit until first win so that script can explain it.
    @updateReplayability()
    @updateLadderSubmissionViews()

  attachTo: (spellView) ->
    @$el.detach().prependTo(spellView.toolbarView.$el).show()

  castShortcutVerbose: ->
    shift = $.i18n.t 'keyboard_shortcuts.shift'
    enter = $.i18n.t 'keyboard_shortcuts.enter'
    "#{shift}+#{enter}"

  castVerbose: ->
    @castShortcutVerbose() + ': ' + $.i18n.t('keyboard_shortcuts.run_code')

  castRealTimeVerbose: ->
    castRealTimeShortcutVerbose = (if @isMac() then 'Cmd' else 'Ctrl') + '+' + @castShortcutVerbose()
    castRealTimeShortcutVerbose + ': ' + $.i18n.t('keyboard_shortcuts.run_real_time')

  onRunButtonClick: (e) ->
    Backbone.Mediator.publish 'tome:manual-cast', { realTime: false }

  onUpdateButtonClick: (e) ->
    Backbone.Mediator.publish 'tome:updateAether'

  onNextButtonClick: (e) ->
    if @winnable and @options.level.get('ozariaType') == 'capstone'
      @options.session.recordScores @world?.scores, @options.level
      capstoneStage = @options.capstoneStage # passed in from PlayLevelView->TomeView
      finalStage = GoalManager.maxCapstoneStage(@options.level.get('additionalGoals'))
      args = {
        showModal: true
        manual: true
        capstoneInProgress: capstoneStage <= finalStage
      }
      Backbone.Mediator.publish 'level:show-victory', args

  onSpellChanged: (e) ->
    @updateCastButton()

  onCastSpells: (e) ->
    return if e.preload
    @casting = true

    # TODO: replace with Ozaria sound
    # if @hasStartedCastingOnce  # Don't play this sound the first time
    #   @playSound 'cast', 0.5 unless @options.level.isType('game-dev')

    @hasStartedCastingOnce = true
    @updateCastButton()

  onManualCastDenied: (e) ->
    wait = moment().add(e.timeUntilResubmit, 'ms').fromNow()
    #@playSound 'manual-cast-denied', 1.0   # find some sound for this?
    noty text: "You can try again #{wait}.", layout: 'center', type: 'warning', killer: false, timeout: 6000

  onNewWorld: (e) ->
    @casting = false
    if @hasCastOnce  # Don't play this sound the first time

      # TODO: replace with Ozaria sound
      # @playSound 'cast-end', 0.5 unless @options.level.isType('game-dev')

      # Worked great for live beginner tournaments, but probably annoying for asynchronous tournament mode.
      myHeroID = if me.team is 'ogres' then 'Hero Placeholder 1' else 'Hero Placeholder'
      if @autoSubmitsToLadder and not e.world.thangMap[myHeroID]?.errorsOut and not me.get('anonymous')
        _.delay (=> @ladderSubmissionView?.rankSession()), 1000 if @ladderSubmissionView
    @hasCastOnce = true
    @updateCastButton()
    @world = e.world

  onPlaybackEnded: (e) ->
    if @winnable and @options.level.get('ozariaType') != 'capstone'
      Backbone.Mediator.publish 'level:show-victory', { showModal: true, manual: true }

  onNewGoalStates: (e) ->
    @winnable = e.overallStatus is 'success'
    # Changing an img's src in CSS is poorly supported in browsers so we're doing it manually here:
    @$el.find('#next > .active-button').attr('src', '/images/ozaria/level/Button_' + (if @winnable then 'Active.png' else 'Inactive.png'))

  onGoalsCalculated: (e) ->
    # When preloading, with real-time playback enabled, we highlight the submit button when we think they'll win.
    return unless e.god is @god
    return unless e.preload
    return if @options.level.get 'hidesRealTimePlayback'
    return if @options.level.get('slug') in ['course-thornbush-farm', 'thornbush-farm']  # Don't show it until they actually win for this first one.
    @onNewGoalStates e

  onPlaybackEndedChanged: (e) ->
    return unless e.ended and @winnable
    @$el.toggleClass 'has-seen-winning-replay', true

  updateCastButton: ->
    return if _.some @spells, (spell) => not spell.loaded

    # TODO: performance: Get rid of async since this is basically the ONLY place we use it
    async.some _.values(@spells), (spell, callback) =>
      spell.hasChangedSignificantly spell.getSource(), null, callback
    , (castable) =>
      Backbone.Mediator.publish 'tome:spell-has-changed-significantly-calculation', hasChangedSignificantly: castable
      @castButton.toggleClass('castable', castable).toggleClass('casting', @casting)
      if @casting
        castText = $.i18n.t('play_level.tome_cast_button_running')
      else if castable or true
        castText = $.i18n.t('play_level.tome_cast_button_run')
        unless @options.level.get 'hidesRunShortcut'  # Hide for first few.
          castText += ' ' + @castShortcut
      else
        castText = $.i18n.t('play_level.tome_cast_button_ran')
      @castButton.text castText
      #@castButton.prop 'disabled', not castable
      @ladderSubmissionView?.updateButton()

  updateReplayability: =>
    return if @destroyed
    return unless @options.level.get 'replayable'
    timeUntilResubmit = @options.session.timeUntilResubmit()
    disabled = timeUntilResubmit > 0
    submitButton = @$el.find('.submit-button').toggleClass('disabled', disabled)
    submitAgainLabel = submitButton.find('.submit-again-time').toggleClass('secret', not disabled)
    if disabled
      waitTime = moment().add(timeUntilResubmit, 'ms').fromNow()
      submitAgainLabel.text waitTime

  loadMirrorSession: ->
    # Future work would be to only load this the first time we are going to submit (or auto submit), so that if we write some code but don't submit it, the other session can still initialize itself with it.
    url = "/db/level/#{@options.level.get('slug') or @options.level.id}/session"
    url += "?team=#{if me.team is 'humans' then 'ogres' else 'humans'}"
    mirrorSession = new LevelSession().setURL url
    @mirrorSession = @supermodel.loadModel(mirrorSession, {cache: false}).model
    @listenToOnce @mirrorSession, 'sync', ->
      @ladderSubmissionView?.mirrorSession = @mirrorSession

  updateLadderSubmissionViews: ->
    @removeSubView subview for key, subview of @subviews when subview instanceof LadderSubmissionView
    placeholder = @$el.find('.ladder-submission-view')
    return unless placeholder.length
    @ladderSubmissionView = new LadderSubmissionView session: @options.session, level: @options.level, mirrorSession: @mirrorSession
    @insertSubView @ladderSubmissionView, placeholder
