
const otherRoutes = require('./other_routes');

// module.exports = function(app, db, s3, multer) {
//     otherRoutes(app, db, s3, multer);
//     //more routes
// }

module.exports = function(app, s3, multer) {
    otherRoutes(app, s3, multer);
    //more routes
}