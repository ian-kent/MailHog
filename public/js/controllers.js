var mailhogApp = angular.module('mailhogApp', []);

mailhogApp.controller('MailCtrl', function ($scope, $http) {
  $scope.refresh = function() {
    $http.get('/api/v1/messages').success(function(data) {
      $scope.messages = data;
    });
  }
  $scope.refresh();

  $scope.date = function(timestamp) {
  	return (new Date(timestamp)).toString();
  };

  $scope.selectMessage = function(message) {
  	$scope.preview = message;
  }

  $scope.deleteAll = function() {
  	$('#confirm-delete-all').modal('show');
  }

  $scope.deleteAllConfirm = function() {
  	$('#confirm-delete-all').modal('hide');
  	$http.post('/api/v1/messages/delete').success(function() {
  		$scope.refresh();
  	});
  }
});
