"
I am P3Converter.

I convert field values to objects, taking into account their type.

I known the character encoding and timezone of the current database connection.
"
Class {
	#name : #P3Converter,
	#superclass : #Object,
	#instVars : [
		'encoder',
		'timezone',
		'map',
		'stringWriteStream',
		'asciiReadStream',
		'asciiWriteStream'
	],
	#category : 'P3'
}

{ #category : #accessing }
P3Converter class >> supportedTypes [
	"Return the list of PostgreSQL internal type names that we can convert to objects."
	
	^ self typeMap values collect: #first
]

{ #category : #accessing }
P3Converter class >> typeMap [
	^ IdentityDictionary newFromPairs: #(
			16 #(bool #convertBooleanFrom:length:description:) 
			17 #(bytea #convertByteArrayFrom:length:description:) 
			20 #(int8 #convertIntegerFrom:length:description:) 
			21 #(int2 #convertIntegerFrom:length:description:) 
			23 #(int4 #convertIntegerFrom:length:description:) 
			26 #(oid #convertIntegerFrom:length:description:) 
			700 #(float4 #convertFloatFrom:length:description:) 
			701 #(float8 #convertFloatFrom:length:description:) 
			1700 #(numeric #convertScaledDecimalFrom:length:description:) 
			19 #(name #convertStringFrom:length:description:) 
			25 #(text #convertStringFrom:length:description:) 
			1042 #(bpchar #convertStringFrom:length:description:) 
			1043 #(varchar #convertStringFrom:length:description:) 
			1082 #(date #convertDateFrom:length:description:) 
			1083 #(time #convertTimeFrom:length:description:) 
			1114 #(timestamp #convertDateAndTimeWithoutTimezoneFrom:length:description:) 
			1184 #(timestamptz #convertDateAndTimeFrom:length:description:)
			114 #(json #convertJsonFrom:length:description:)
			3802 #(jsonb #convertJsonFrom:length:description:)
			2278 #(void #convertVoidFrom:length:description:)
			2950 #(uuid #convertUuidFrom:length:description:)
			
		)
]

{ #category : #'input/output' }
P3Converter >> asciiCStringFrom: binaryStream [
	| byte |
	asciiWriteStream reset.
	[ (byte := binaryStream next) = 0 ]
		whileFalse: [ asciiWriteStream nextPut: byte asCharacter ].
	^ asciiWriteStream contents
]

{ #category : #private }
P3Converter >> asciiStreamFor: bytes length: length [
	| asciiString |
	asciiString := asciiReadStream originalContents.
	asciiString size < length
		ifTrue: [ 
			asciiReadStream := (asciiString := String new: ((length // 64) + 1) * 64) readStream ].
	bytes next: length into: asciiString. "implicit cheap ASCII conversion"
	asciiReadStream setFrom: 1 to: length.
	^ asciiReadStream 
]

{ #category : #converting }
P3Converter >> convert: bytes length: length description: description [

	| type lambda |
	
	type := map at: description typeOid 
		ifAbsent: [ self error: 'P3 cannot convert typeOid ', description typeOid asString ].
		
	lambda := type second.
	
	^ lambda isSymbol 
		ifTrue: [ self perform: type second with: bytes with: length with: description ]
		ifFalse: [ lambda value: bytes value: length value: description ]
]

{ #category : #converting }
P3Converter >> convertBooleanFrom: bytes length: length description: description [
	self assert: length = 1.
	^ bytes next = $t charCode
]

{ #category : #converting }
P3Converter >> convertByteArrayFrom: bytes length: length description: description [
	| size byteArray digitValues |
	self assert: (bytes next: 2) = #[92 120]. "\x"
	size := (length - 2) // 2.
	digitValues := #(-1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 0 1 2 3 4 5 6 7 8 9 -1 -1 -1 -1 -1 -1 -1 10 11 12 13 14 15 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 10 11 12 13 14 15 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1).
	byteArray := ByteArray new: size.
	1 to: size do: [ :index | | value |
		value := digitValues at: bytes next + 1.
		value := (value bitShift: 4) + (digitValues at: bytes next + 1).
		byteArray at: index put: value ].
	^ byteArray 
]

{ #category : #converting }
P3Converter >> convertDateAndTimeFrom: bytes length: length description: description [
	"TIMESTAMP WITH TIME ZONE (TIMESTAMPTZ) is stored internally in Postgres as UTC, but represented in the timezone of the connection, with a correct offset added. In other words, Postgres does the necessary shifting, we just have to read the result"
	
	^ DateAndTime readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : #converting }
P3Converter >> convertDateAndTimeWithoutTimezoneFrom: bytes length: length description: description [
	"TIMESTAMP WITHOUT TIME ZONE (TIMESTAMP) is stored internally in Postgres the way it was inserted, its representation remains constant, with no offset added. We use the timezone of the connection to do the necessary shifting. This assumes that the timezones used during insert/update and query are the same."

	| timestamp offset |
	timestamp := DateAndTime readFrom: (self asciiStreamFor: bytes length: length) defaultOffset: Duration zero.
	offset := self timezone offsetForTimestamp: timestamp.
	^ timestamp translateTo: offset
]

{ #category : #converting }
P3Converter >> convertDateFrom: bytes length: length description: description [
	^ Date readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : #converting }
P3Converter >> convertFloatFrom: bytes length: length description: description [
	^ Float readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : #converting }
P3Converter >> convertIntegerFrom: bytes length: length description: description [
	^ Integer readFrom: (self asciiStreamFor: bytes length: length) base: 10
]

{ #category : #converting }
P3Converter >> convertJsonFrom: bytes length: length description: description [
	| input |
	input := ZnLimitedReadStream on: bytes limit: length.
	input := ZnCharacterReadStream on: input encoding: self encoder. 
	^ (NeoJSONReader on: input)
			mapClass: NeoJSONObject;
			propertyNamesAsSymbols: true;
			next
]

{ #category : #converting }
P3Converter >> convertScaledDecimalFrom: bytes length: length description: description [
	^ ScaledDecimal readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : #converting }
P3Converter >> convertStringFrom: bytes length: length description: description [
	| endPosition |
	length = 0 ifTrue: [ ^ '' ].
	endPosition := bytes position + length.
	stringWriteStream reset.
	[ stringWriteStream nextPut: (encoder nextFromStream: bytes) ]
			doWhileTrue: [ bytes position < endPosition ].
	^ stringWriteStream contents
]

{ #category : #converting }
P3Converter >> convertTimeFrom: bytes length: length description: description [
	^ Time readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : #converting }
P3Converter >> convertUuidFrom: bytes length: length description: description [
	
	^ UUID nilUUID readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : #converting }
P3Converter >> convertVoidFrom: bytes length: length description: description [
	self assert: length = 0.
	^ nil
]

{ #category : #'input/output' }
P3Converter >> encodedCStringFrom: binaryStream [
	stringWriteStream reset.
	[ binaryStream peekFor: 0 ]
		whileFalse: [ stringWriteStream nextPut: (encoder nextFromStream: binaryStream) ].
	^ stringWriteStream contents
]

{ #category : #accessing }
P3Converter >> encoder [
	^ encoder ifNil: [ encoder := ZnCharacterEncoder utf8 ]
]

{ #category : #accessing }
P3Converter >> encoder: anObject [
	encoder := anObject
]

{ #category : #initalize }
P3Converter >> initialize [
	super initialize.
	asciiReadStream := String new readStream.
	asciiWriteStream := String new writeStream.
	stringWriteStream := String new writeStream.
	self initializeTypeMap
]

{ #category : #initalize }
P3Converter >> initializeFrom: properties [
	| serverTimezone serverEncoder |
	serverTimezone := properties at: 'TimeZone' ifAbsent: [ 'GMT' ].
	serverTimezone := ZTimezone id: serverTimezone.
	self timezone: serverTimezone.
	serverEncoder := properties at: 'client_encoding' ifAbsent: [ 'UTF8' ].
	serverEncoder := ZnCharacterEncoder newForEncoding: serverEncoder.
	self encoder: serverEncoder
]

{ #category : #initalize }
P3Converter >> initializeTypeMap [
	map := self class typeMap
]

{ #category : #accessing }
P3Converter >> mapOid: anOoid type: aTypename to: aBlockOrSymbol [

	^ map at: anOoid put: { aTypename . aBlockOrSymbol }	
]

{ #category : #printing }
P3Converter >> printOn: stream [
	super printOn: stream.
	stream nextPut: $(.
	stream print: self encoder identifier.
	stream space.
	self timezone ifNotNil: [ :tmz | stream print: tmz id ].
	stream nextPut: $)
]

{ #category : #accessing }
P3Converter >> timezone [
	^ timezone
]

{ #category : #accessing }
P3Converter >> timezone: anObject [
	timezone := anObject
]
