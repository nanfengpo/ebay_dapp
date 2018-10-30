/**
 * 本模块只用于mongoDB数据库的读写。作用是提高查询和过滤的效率。
 * 【注意】即使是MongoDB，也不会存储产品的图片本身，而是存储图片在ipfs的hash值
 */

var ecommerce_store_artifacts = require('./build/contracts/EcommerceStore.json')
var contract = require('truffle-contract')
var Web3 = require('web3')
var provider = new Web3.providers.HttpProvider("http://localhost:8545");
var EcommerceStore = contract(ecommerce_store_artifacts);
EcommerceStore.setProvider(provider); // 设置以太坊网络的api
/*
 - start gananche-cli
 - truffle migrate
 - node server.js
 - truffle exec seed.js
 -- check mondodb
   show dbs;
   use ebay_dapp;
  db.productmodels.find({})
 */
//Mongoose setup to interact with the mongodb database
var mongoose = require('mongoose');
mongoose.Promise = global.Promise;
var ProductModel = require('./product');  // 获取product.js中的数据库模型

const options = { // 连接mongoDB的选项
  useMongoClient: true,
  reconnectTries: Number.MAX_VALUE, // Never stop trying to reconnect
  reconnectInterval: 500, // Reconnect every 500ms
  poolSize: 10, // Maintain up to 10 socket connections
  // If not connected, return errors immediately rather than waiting for reconnect
  bufferMaxEntries: 0
};
mongoose.connect("mongodb://localhost:27017/ebay_dapp",options);
var db = mongoose.connection;
db.on('error', console.error.bind(console, 'MongoDB connection error:'));

// Express server which the frontend with interact with
var express = require('express');
var app = express();

app.use(function(req, res, next) {
  res.header("Access-Control-Allow-Origin", "*"); // 允许来自任何ip的请求
  res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept"); // 允许的header字段
  next();
});

app.listen(3000, function() {
  console.log('Ebay Ethereum server listening on port 3000!');
});

function saveProduct(product) {
  ProductModel.findOne({ 'blockchainId': product._productId.toLocaleString() }, function (err, dbProduct) {

    if (dbProduct != null) {
      return;
    }

    var p = new ProductModel({name: product._name, blockchainId: product._productId, category: product._category,
      ipfsImageHash: product._imageLink, ipfsDescHash: product._descLink, auctionStartTime: product._auctionStartTime,
      auctionEndTime: product._auctionEndTime, price: product._startPrice, condition: product._productCondition,
      productStatus: 0});
    p.save(function (err) {
      if (err) {
        handleError(err);
      } else {
        ProductModel.count({}, function(err, count) {
          console.log("count is " + count);
        })
      }
    });
  })
}

// 监听新产品事件的函数
function setupProductEventListner() {
  let productEvent;
  EcommerceStore.deployed().then(function(i) {
    productEvent = i.NewProduct({fromBlock: 0, toBlock: 'latest'});

    productEvent.watch(function(err, result) {
      if (err) {
        console.log(err)
        return;
      }
      saveProduct(result.args);
    });
  })
}

// 执行监听新产品事件的函数
setupProductEventListner();

// 只提供这一个get请求的api。
app.get('/products', function(req, res) {
  current_time = Math.round(new Date() / 1000);
  query = { productStatus: {$eq: 0} }

  if (Object.keys(req.query).length === 0) {
    query['auctionEndTime'] = {$gt: current_time}
  } else if (req.query.category !== undefined) {
    query['auctionEndTime'] = {$gt: current_time}
    query['category'] = {$eq: req.query.category}
  } else if (req.query.productStatus !== undefined) {
    if (req.query.productStatus == "reveal") {
      query['auctionEndTime'] = {$lt: current_time, $gt: current_time - (60*60)}
    } else if (req.query.productStatus == "finalize") {
      query['auctionEndTime'] = { $lt: current_time - (60*60) }
      query['productStatus'] = {$eq: 0}
    }
  }

  ProductModel.find(query, null, {sort: 'auctionEndTime'}, function (err, items) {
    console.log(items.length);
    res.send(items);
  })
});
