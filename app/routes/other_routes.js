
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const cmd = require('node-cmd');
const mv = require('mv');

const AdmZip = require('adm-zip');


//removed db from second position
module.exports = function(app, s3, upload) {

  //basic variables that I need
  var bucketName = 'pw-energylab-west'; //TODO: make this part of the user request body
  //local
  var pathToUnzipLocation = '/tmp/pw-uploads/'; //unused, there as a placeholder if needed.
  var pathToDownloadLocation = '/tmp/pw-uploads/';
  var ipaddressOfServer = '';
  var pathToRakeFile = '/Users/chienharriman/PWSpeedTestDocker/speedrequestserver/pwspeedrequest/scripts/OpenStudio-analysis-spreadsheet';
  var projectspath = "/Users/chienharriman/PWSpeedTestDocker/speedrequestserver/pwspeedrequest/scripts/OpenStudio-analysis-spreadsheet/projects";
  var seedpath = "/Users/chienharriman/PWSpeedTestDocker/speedrequestserver/pwspeedrequest/scripts/OpenStudio-analysis-spreadsheet/seeds";
  //incoming
  var key;
  var filename;

  function* manageProcesses() 
  {
    console.log("trying to manage processes.");
    let result = yield storeFileLocally(key,filename);
    console.log("Result of storing file locally");
    let rakeResult = yield runRake(result);
  };
  //multer s3 is being used to upload a single file to S3, see upload.single below
  //os_serverpackage is key associated with the zip file in the request header sent by the user
  app.post('/projectupload', upload.single('os_serverpackage'), (req, res, next) => {
    // Path to save the files
    //console.log(res);
    if(req.method == 'POST')
    {
      //validate is multi-part form?
      //check on size of incoming?
      if(req.file)
      {
        var key = req.file.key;
        //console.log("request file: ", req.file);
        //console.log("request body: ", req.body);
        var filename = req.file.originalname.substring(0,req.file.originalname.length - 4);
        console.log("key ", key);
        console.log("filename ", filename);

        let iterator = manageProcesses(key,filename);

        storeFileLocally(key, filename)
          .then((res) => runRake(res), (err) => { console.log("Something went wrong running the rakefile: ", err); }) //TODO: add failure routes
          .then(() => res.status(200).json("Your file have been successfully uploaded to pw speed server.  Your request is now being run in the cloud."))
          .catch(console.log.bind(console));
      }
      else
      {
        res.status(400).
        res.send("Error: this request contains multiple zip files.  You should only be sending one zip file at a time.");
      }
    }
  });

  app.post('/projectuploads', upload.array('os_serverpackages'), (req, res, next) => {
    res.status(500);
    res.send("Empty route, not currently available for external use.");
  });
  

  function cleanUp(filepath)
  {
    //the goal here is to cleanup all the places where files were added.  This is to save space!
    return new Promise(function(resolve,reject){
      console.log("Cleaning up");
      resolve("Done");
    })
  }

  function timeout(delay) {
    return new Promise(function(resolve,reject){
      setTimeout(resolve,delay);
    })
  }

  function runRake(xlfinal)
  {
    return new Promise(function(resolve,reject){
      //old test
      //if path.exists, great, if it doesn't ... throw an error
      //now run a child process to get external files to do their stuff
      //let's try the bash shell
      console.log("Trying the bash shell to run rake")
      var exec = cp.exec('bundle exec rake run_custom[http://35.166.248.79:8080,/Users/chienharriman/PWSpeedTestDocker/speedrequestserver/pwspeedrequest/scripts/OpenStudio-analysis-spreadsheet/projects/lhs_discrete_continuous_example.xlsx]',
        [{cwd:pathToRakeFile}], function(error, stdout,stderr){
          console.log("Ran rake file", stdout);
        });
      //run via a ruby script
      // var rubychild = cp.spawn('ruby',['scripts/OpenStudio-analysis-spreadsheet/rakelaunch.rb']);
      // rubychild.stdout.on('data', (data) => {
      //   console.log(data.toString());
      // });

      // rubychild.stderr.on('data', (data) => {
      //   console.log(data.toString());
      //   //TODO: what do we want to do in the case of an error?
      // });

      // rubychild.on('exit', (code) => {
      //   console.log(`Child exited with code ${code}`);
      // });

      resolve(xlfinal);

    });
    
  }

  function storeFileLocally(inkey, zipfilename) {

    return new Promise(function(resolve, reject) {
      try 
      {
        //1 - renove illegal characters and remove the .zip at the end
        var cleankey = inkey.replace('|','_');
        cleankey = cleankey.substring(0,cleankey.length - 4);
        //2 - check if filepath exists, and if not, create it
        if(!fs.existsSync(pathToDownloadLocation))
        {
          fs.mkdir(pathToDownloadLocation, function(err){
            if(err)
            {
              return console.error(err);
            }
            console.log("Base download directory created successfully");
          })
        }
        var file = fs.createWriteStream(pathToDownloadLocation+cleankey+'.zip')
        file.on('finish', function(){
          console.log('Zip file written');
          //TODO: add error handling to deal with case where path and zip folder do not exist.
          var zip = new AdmZip(pathToDownloadLocation+cleankey+'.zip')
          zip.extractAllTo(/*target path*/pathToDownloadLocation+cleankey, /*overwrite*/true);
          console.log("Done extracting zip file.");
          //move to the proper location in the analysis-spreadsheet folder

        });
        var filestream = s3.getObject({Bucket:bucketName, Key:inkey}).createReadStream().on('error', function(err){
          console.log("Create readstream error:", err);
          throw err;
        }).pipe(file);
        filestream.on('finish', () =>{
          console.log("Saved unzipped files locally to drive.")
          //we resolve to this so the ruby script can find the excel spreadsheet and seed model path it needs for its execution
          var osmfinal = "";
          var xlfinal = "";
          let filepath = pathToDownloadLocation+cleankey+"/"+zipfilename
          console.log("looking for excel files in: ", filepath);
          if(fs.existsSync(filepath))
          {
            console.log("Valid path.");
            //1 - move the excel file and possibly the seed model to the proper location
            let files = fs.readdirSync(filepath);
            for(var f in files)
            {
              if(path.extname(files[f]) == ".osm")
              {
                let osmpath = filepath+'/'+files[f];
                osmfinal = seedpath+'/'+files[f];
                mv(osmpath,osmfinal, function(err) {
                  if(err)
                  {
                    console.log("Something went wrong when trying to move the .osm file") //TODO: improve the response so it is sent to user, not fail
                  }
                  else
                  {
                    console.log(".osm file moved to " + osmfinal);
                  }
                });
              }
              else if (path.extname(files[f]) == ".xlsx")
              {
                let xlpath = filepath+'/'+files[f];
                xlfinal = projectspath+'/'+files[f];
                mv(xlpath,xlfinal, function(err) {
                  if(err)
                  {
                    console.log("Something went wrong when trying to move the .xlsx file") //TODO: improve the response so it is sent ot user, not fail
                  }
                  else
                  {
                    console.log(".xlsx file moved to " + xlfinal);
                  }
                });
              }
            }
          }
          resolve(xlfinal); 
        })
      }
      catch (e) {
        reject(e);
      }
      
    });
  }
}