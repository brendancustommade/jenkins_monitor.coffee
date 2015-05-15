# Description:
#   I'll keep an eye on Jenkins for you
#
# Commands:
#   hubot jenkins monitor [branchName] - tells me to monitor a branches test results and notify you directly when they have finished
#   hubot jenkins stop monitor on [branchName] - tell me to no longer monitor a branch for you
#   hubot jenkins list monitors - displays a list of all branches I am currently monitoring
#   hubot jenkins results for [branchName] - grabs current test status for branch name and displays in current room

Utils = require "./utilities"

devOpsHipChatIds = process.env.HUBOT_DEVOPS_USER_IDS
urlRegex = /(https?:\/\/[^\s]+)/g;

# our queue to monitor different branches
class Monitors
  constructor: (@robot) ->
    @cache = []
    @current_timeout = null
    @utils = new Utils
    @refresh_rate = 60000 # check every minute (maybe want to change)

    @robot.brain.on 'loaded', =>
      if @robot.brain.data.monitors
        @cache = @robot.brain.data.monitors

        # start a psuedo poller
        @queue()

  # adds a single monitor to our list
  add: (monitor) ->
    # we should only add this monitor if we're not already watching
    # TODO: maybe check the user so two users can monitor the same branch
    if monitor.branchName not in @cache
      @cache.push monitor
      @robot.brain.data.monitors = @cache

  # removes a monitor for given branchName
  remove: (branchName) ->
    @cache = (x for x in @cache when x.branchName != branchName)
    @robot.brain.data.monitors = @cache

  # removes first element in the list of monitors
  removeFirst: ->
    monitor = @cache.shift()
    @robot.brain.data.monitors = @cache
    return monitor

  # starts are polling process to check all branches
  queue: ->
    setTimeout(f = (=>
        @checkAllBranches()
        setTimeout(f, @refresh_rate)
    ), @refresh_rate)

  # display all of our monitors
  displayAll: (msg) ->
    if @robot.brain.data.monitors.length > 0
        for monitor in @robot.brain.data.monitors
          msg.send @displayMonitor monitor
    else
      msg.reply "No active monitors found."

  # how we display an individual monitor
  displayMonitor: (monitor) ->
    return "#{monitor.branchName} - #{monitor.userName}"

  checkAllBranches: ->

    if @robot.brain.data.monitors.length > 0
        for monitor in @robot.brain.data.monitors
          user = @robot.brain.userForId monitor.userId
          success = (url) =>
            @robot.send user, @successMessage url
            @remove monitor.branchName
          fail = (url) ->
            @robot.send user, @failMessage url
            @remove monitor.branchName
          @checkBranch monitor.branchName, success, fail

  checkBranch: (branchName, success, fail) ->
    # TODO: when we upgrade node versions, we can force this command to be syncronous
    # so we don't have to deal with callbacks
    output = utils.captureFabCommand "branch.test_results:#{branchName}"
    output.stdout.on 'data', (data) =>
      url = data.match(urlRegex)[0].replace('\')', '')
      if ~data.indexOf "failure"
        fail url
      else if ~data.indexOf "success"
        success url

  successMessage: (url) ->
    return "Great success! (borat) Your tests have passed!.  Tests results are here: #{url}"

  failMessage: (url) ->
    return "Ahhh (poo), your tests failed!  Test results are here: #{url}"

class Monitor
  constructor: (@msg_envelope, @branchName) ->
    @userId = @msg_envelope.user.id
    @userName = @msg_envelope.user.name
    @userMentionName = @msg_envelope.user.mention_name

module.exports = (robot) ->

  @utils = new Utils

  monitors = new Monitors robot

  robot.respond /jenkins monitor @?([\w_.-]+)/i, (msg) ->
    branchName = utils.removeWhitespace msg.match[1]
    roomId = utils.getRoomId msg
    monitor = new Monitor msg.envelope, branchName
    monitors.add monitor
    msg.reply "Ok, I'll keep an eye on it for you."

  robot.respond /jenkins list monitors/i, (msg) ->
    msg.reply "I'm keeping an eye on the following branches."
    monitors.displayAll msg

  robot.respond /jenkins stop monitor on @?([\w_.-]+)/i, (msg) ->
    branchName = utils.removeWhitespace msg.match[1]
    roomId = utils.getRoomId msg
    monitors.remove branchName
    msg.reply "Ok, I've removed it from my list. You're on your own now."

  robot.respond /jenkins results for @?([\w_.-]+)/i, (msg) ->
    branchName = utils.removeWhitespace msg.match[1]
    msg.reply "Checking test status for #{branchName}..."
    success = (url) ->
      msg.reply monitors.successMessage url
    fail = (url) ->
      msg.reply monitors.failMessage url
    monitors.checkBranch branchName, success, fail

