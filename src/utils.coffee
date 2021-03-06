{exec} = require('child_process')
parseURL = require('url').parse
heroku = require 'heroku'
fs = require 'fs'

MSON = require 'mongoson'

module.exports = utils = {}
utils.parseConnectionString = (connectionString) ->
  parsedURL = parseURL connectionString
  info = {}
  info.hostname = parsedURL.hostname
  info.port = parsedURL.port
  info.host = if info.port then "#{info.hostname}:#{info.port}" else info.hostname
  info.database = info.db = parsedURL.pathname && parsedURL.pathname.replace(/\//g, '')
  [info.username,info.password] = parsedURL.auth.split(':') if parsedURL.auth
  info

utils.dumpDatabase = (connectionString, dirName, next) ->
  connectionParameters = utils.parseConnectionString connectionString
  commandOptions = makeCommandOptions connectionParameters
  commandOptions.out = dirName
  commandArguments = makeCommandArguments commandOptions
  console.log argumentString = makeArgumentString commandArguments
  exec "mongodump#{argumentString}", (err, stdOut, stdErr) ->
    return next err if err
    return next null, stdOut, stdErr

utils.restoreDatabase = (connectionString, dirName, next) ->
  utils.findDumpDirName dirName, (err, actualDirName) ->
    console.log "Using #{actualDirName}"
    connectionParameters = utils.parseConnectionString connectionString
    commandOptions = makeCommandOptions connectionParameters
    commandOptions.drop = true
    commandArguments = makeCommandArguments commandOptions, actualDirName
    console.log argumentString = makeArgumentString commandArguments
    exec "mongorestore#{argumentString}", (err, stdOut, stdErr) ->
      return next err if err
      return next null, stdOut, stdErr

utils.findDumpDirName = (dirName, next) ->
  dirCount = 0
  for entryName in fs.readdirSync dirName
    if fs.statSync("#{dirName}/#{entryName}").isDirectory()
      dirCount += 1 
      lastDirName = entryName
  switch dirCount
    when 0 then next null, dirName # a proper dump dir
    when 1 then next null, dirName + "/" + lastDirName # assume this one is proper
    else next "Dump dir contains multiple directories."
  
utils.dumpHerokuMongoHQDatabase = (appName, dirName, next) ->
  utils.findHerokuMongoHQURL appName, (err, url) ->
    return next err if err
    return utils.dumpDatabase url, dirName, next

utils.restoreHerokuMongoHQDatabase = (appName, dirName, next) ->
  utils.findHerokuMongoHQURL appName, (err, url) ->
    return next err if err
    return utils.restoreDatabase url, dirName, next

utils.findHerokuMongoHQURL = (appName, next) ->
  return next "Cannot find environment variable HEROKU_API_KEY" unless process.env['HEROKU_API_KEY']
  herokuClient = new heroku.Heroku key: process.env['HEROKU_API_KEY']
  herokuClient.get_config_vars appName, (err, herokuConfig) ->
    return next err if err
    return next "Cannot find MONGOHQ_URL in config of #{appName}." unless herokuConfig.MONGOHQ_URL
    return next null, herokuConfig.MONGOHQ_URL

utils.makeFindCommand = (collectionName, query, options = {}) ->
  command  = "db.#{collectionName}.find(#{MSON.stringify query}"
  command += ",#{JSON.stringify options.fields}" if options.fields
  command += ")"
  command += ".sort(#{JSON.stringify options.sort})" if options.sort
  command

makeCommandOptions = (connParams) ->
  options = {}
  options.db = connParams.db
  options.host = connParams.host unless connParams.host is "localhost"
  options.username = connParams.username if connParams.username
  options.password = connParams.password if connParams.password
  options

makeCommandArguments = (options, object) ->  
  args = []
  for name, value of options 
    args.push "--#{name}" unless value is false
    args.push "#{value}" unless value is true or value is false
  args.push object if object
  args

makeArgumentString = (args) ->
  str = ""
  str += " \"#{arg}\"" for arg in args
  str