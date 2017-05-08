const express = require('express');
const MongoClient = require('mongodb').MongoClient;
const bodyParser = require('body-parser');
const db = require('./config/db');
const AWS = require('aws-sdk');
const multer = require('multer');
const multerS3 = require('multer-s3');

var s3 = new AWS.S3({ params: {Bucket: 'pw-energylab-west' } });
var myConfig = new AWS.Config({
  region: 'us-west-2'
});

AWS.config.getCredentials(function(err) {
  if (err) console.log(err.stack); // credentials not loaded
  else console.log("Access Key:", AWS.config.credentials.accessKeyId);
})
var diskstorage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, '/tmp/my-uploads')
  },
  filename: function (req, file, cb) {
    cb(null, file.fieldname + '-' + Date.now())
  }
})

var awsStorage = multerS3({
  s3: s3,
  bucket: 'pw-energylab-west', //required
  metadata: function(req,file,cb) {
    cb(null, {userid: req.body.userid})
  },
  key: function(req,file,cb) {
    console.log(req.body);
    cb(null,req.body.userid+"|"+Date.now().toString());
  }
});

var upload = multer({ storage: awsStorage, limits:'4MB' }) //multer upload var

const app = express();

const port = 8080;

app.use(bodyParser.urlencoded({ extended: true }));
app.use(errorHandler)

function errorHandler(err, req, res, next) {
  res.status(500).json('error', {error: err});
}
//any other restrictions I want to put here?
//app.use(bodyParser.json())

//MongoClient.connect(db.url, (err, database) => {
  //if(err) { return console.log(err); }

  // require('./app/routes')(app, database, s3, upload
  require('./app/routes')(app, s3, upload);
  app.listen(port, () => {
    console.log('PW speed request server live on port ' + port); 
  });
//});


