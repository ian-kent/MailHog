var mailhogApp = angular.module('mailhogApp', []);

mailhogApp.controller('MailCtrl', function ($scope, $http) {
  $http.get('/api/v1/messages').success(function(data) {
    $scope.messages = data;
  });

  $scope.date = function(timestamp) {
  	return (new Date(timestamp)).toString();
  };

  $scope.selectMessage = function(message) {
  	$scope.preview = message;
  }
});
