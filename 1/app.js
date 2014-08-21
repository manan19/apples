// Outputs total number of trades executed, volume in USD and volume in BTC on bitme.com

var https = require('https');

var bitmeVolume = function(currencypair) {
  https.get('https://bitme.com/rest/compat/trades/'+currencypair+'?since=0', function(res) {
    var data = '';
    res.on('end', function () {
      // console.log(data);
      var trades = JSON.parse (data);
      var totalVolumeUSD = 0, totalVolumeBTC = 0;
      for(var i = 0; i < trades.length; i++) {
        totalVolumeUSD += trades[i].price * trades[i].amount;
        totalVolumeBTC += trades[i].amount * 1;      
      }

      console.log('-----');
      console.log(currencypair);
      console.log(trades.length + ' trades since ' + new Date(trades[0].date*1000));
      console.log('Volume in USD = ' + Math.round(totalVolumeUSD*100/1000000)/100 + 'M');
      console.log('Volume in BTC = ' + totalVolumeBTC);

    });

    res.on('data', function (chunk) {
      data += chunk;
    });
  });
}

bitmeVolume('BTCUSD');

