yahooFinance = require('yahoo-finance')
fs = require('fs')
_ = require('underscore')

DEBUG = false
useCache = false

console.debug = (str) ->
  if DEBUG
    console.log str

toUSD = (number) ->
  number = number.toString()
  dollars = number.split('.')[0]
  cents = (number.split('.')[1] or '') + '00'
  dollars = dollars.split('').reverse().join('').replace(/(\d{3}(?!$))/g, '$1,').split('').reverse().join('')
  '$' + dollars + '.' + cents.slice(0, 2)

# This method knows the future. buys at local minimum, sells at local maximum, highest profit.
potentialReturns = (prices, minSellGap) ->
  transaction = undefined
  owned = undefined
  lastBuyPrice = undefined
  returnRatio = 1
  numOfTransactions = 0
  nextSell = undefined
  minSellGap = 0  unless minSellGap

  sell = (index) ->
    return  if index <= nextSell
    transaction = ' <- sell'
    owned = false
    numOfTransactions++
    nextSell = index + minSellGap
    returnRatio *= prices[index] / lastBuyPrice
    return

  buy = (index) ->
    transaction = ' <- buy'
    owned = true
    numOfTransactions++
    lastBuyPrice = prices[index]
    return

  # potentalReturns
  i = 0

  while i < prices.length
    transaction = ''
    if i is 0
      buy i
    else if i is prices.length - 1
      sell i
    else
      if prices[i] > prices[i + 1] and owned
        sell i
      else buy i  if prices[i] < prices[i + 1] and not owned
    i++
    console.debug prices[i] + transaction

  console.debug numOfTransactions
  returnRatio

# This method trails the max value before initiating a sell
intelligentTrailReturns = (prices, minSellGap, buyingTrailPercent, sellingTrailPercent, lossesAllowed) ->
  transaction = undefined
  owned = undefined
  lastBuyPrice = undefined
  returnRatio = 1
  numOfTransactions = 0
  nextSell = undefined
  sellingTrail = 0
  buyingTrail = Infinity
  minSellGap = 0  unless minSellGap

  resetBuyingTrail = ->
    buyingTrail = Infinity
    return

  updateBuyingTrail = (price) ->
    value = price * (100 + buyingTrailPercent) / 100
    buyingTrail = value  if buyingTrail > value
    return

  sell = (index) ->
    if index <= nextSell
      console.debug 'wanted to sell, but could not because of unsettled funds'
      return
    transaction = 'sell'
    owned = false
    numOfTransactions++
    nextSell = index + minSellGap
    resetBuyingTrail()
    updateBuyingTrail prices[index]
    returnRatio *= prices[index] / lastBuyPrice
    console.debug "Last trade was a #{if prices[index] / lastBuyPrice > 1 then 'profit' else 'loss'}"
    console.debug "NET #{ if returnRatio > 1 then 'PROFIT' else 'LOSS'}  #{returnRatio}"
    console.debug "#{lastBuyPrice} #{prices[index]} ";
    return

  updateSellingTrail = (price) ->
    value = price * (100 - sellingTrailPercent) / 100
    sellingTrail = value  if sellingTrail < value
    return

  resetSellingTrail = ->
    sellingTrail = 0
    return

  buy = (index) ->
    transaction = 'buy'
    owned = true
    numOfTransactions++
    lastBuyPrice = prices[index]
    resetSellingTrail()
    updateSellingTrail lastBuyPrice
    return

#  potentalReturns
  for i in [0..prices.length-1]
    transaction = if owned then 'hold' else ''
    if i is 0
      buy i
    else if i is prices.length - 1
      sell i
    else
      if prices[i] < sellingTrail and owned
        if prices[i] > lastBuyPrice or lossesAllowed
          sell i
      else if prices[i] > buyingTrail and not owned
        buy i
    updateSellingTrail prices[i]
    updateBuyingTrail prices[i]

    console.debug "#{prices[i]} <- #{transaction}"
    console.debug " sT #{(Math.round sellingTrail * 100) / 100}"
    console.debug " bT #{(Math.round buyingTrail * 100) / 100}"

  console.debug(numOfTransactions);
  returnRatio

analyze = (quotes, symbol) ->
  investment = 100
  adjCloses = []

  for i in [0..quotes.length-1]
    adjCloses.push quotes[i].adjClose

  vanillaReturns = investment * adjCloses[adjCloses.length - 1] / adjCloses[0]
  maxReturns = investment * potentialReturns(adjCloses)
  trailReturns = 0

  # Global params
  sellGap = 3
  longTermCapitalGainsTaxRate = 15
  shortTermCapitalGainsTaxRate = 28

  minGainToBeBetterThanLTCG = Number (((100 - longTermCapitalGainsTaxRate)/(100 - shortTermCapitalGainsTaxRate) - 1) * 100).toFixed(2)

  console.log "\n#{symbol}"

  console.log "#{quotes[0].date} - #{quotes[quotes.length-1].date}"

  console.log "investment: #{toUSD investment}"
  console.log "vanillaReturns: #{toUSD Math.round vanillaReturns}"
  console.log "maxReturns: #{toUSD Math.round investment * potentialReturns adjCloses, sellGap}"

  console.log 'iTrailReturns'
  console.log "minGainToBeBetterThanLTCG #{minGainToBeBetterThanLTCG}"
  console.log ' bTP%\t sTP%\t Returns\t Net\t Margin\t lossAllowed'

  for lossesAllowed in [true, false]
    for sTP in [1..20]
      for bTP in [1..20]
        trailReturns = investment * intelligentTrailReturns adjCloses, sellGap, bTP, sTP, lossesAllowed
        if trailReturns > vanillaReturns
          bTPPercent = ('0'+bTP).slice(-2)
          sTPPercent = ('0' + sTP).slice(-2)
          iTrailReturns = toUSD Math.round trailReturns
          iTrailNetGain = ((trailReturns / vanillaReturns - 1) * 100).toFixed(2)
          iTrailMarginGain = Number (iTrailNetGain - minGainToBeBetterThanLTCG).toFixed(2)

          if iTrailMarginGain > 0
            console.log " #{bTPPercent}\t #{sTPPercent}\t #{iTrailReturns}\t #{iTrailNetGain}\t #{iTrailMarginGain}\t #{lossesAllowed}"

analyzeMultiple = (err, results) ->
  fs.writeFileSync './sample', JSON.stringify results
  _.each results, (quotes, symbol) ->
    analyze quotes, symbol

if useCache
  results = JSON.parse(fs.readFileSync('./sample'))
  analyzeMultiple null, results
else
  yahooFinance.historical
    symbols: [
#      'aapl'
#      'cmg'
#      'amzn'
#      'sune'
#      'yhoo'
#      'msft'
#      'goog'
#      'fb'
#      'bbry'
#      'ostk'
#      'xom'
#      'lnkd'
#      'tsla'
#      'tm'
#      'scty'
      'gpro'
#      'z'
#      'twtr'
    ]
    from: '2000-01-01'
  , analyzeMultiple
