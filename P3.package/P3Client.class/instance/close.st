initialize-release
close
	"Cleanly close my connection with the server"

	connection
		ifNotNil: [ 
			[ 
				self writeMessage: #[] tag: $X. 
				connection close ] on: Error do: [  ].
			properties at: 'connected' put: 'false'.
			connection := nil ]