#include <math.h>
#include "Accel.h"
#include "printf.h"

module QuickP {
	uses interface Boot;

	/* Interaces for sending and receving messages */
	uses interface AMSend;
	uses interface Receive;
	uses interface Packet;
	uses interface SplitControl as RadioControl;

	/* Timers */
	uses interface Timer<TMilli> as AccelTimer;		/* Timer to sample the accelerometer ~ 54Hz */
	uses interface Timer<TMilli> as StartTimer;		/* Timer to ensure the mote is in ready position for 1 second */
	uses interface Timer<TMilli> as CountDownTimer;		/* Timer for the count down */
	uses interface Timer<TMilli> as FireTimer;		/* Timer to ensure the mote is in fire position for 0.5 seconds */
	uses interface Timer<TMilli> as DrawTimer;		/* Timer for the draw time */
	uses interface Timer<TMilli> as ACKTimer;		/* Timer to ensure that ACK has been received from both motes in 1.5 seconds */
	uses interface Timer<TMilli> as SysTimer;		/* Timer used as seed for the random number generator */

	/* Interface for reading accelerometer values */
	uses interface Read<uint16_t> as ReadY;

	/* Interfaces for LEDs and speaker */
	uses interface Leds;
	uses interface Mts300Sounder;

	/* Interfaces for the random number generator */
	uses interface Random;
	uses interface ParameterInit<uint16_t>;
}
implementation {
	accel_t accelValues;					/* Accelerator values */
	message_t buf_all, buf_base, buf_draw, buf_ref, buf_ack;/* Message buffers */
	uint8_t countDown = 0; 					/* Number of countdown beeps */
	uint16_t draw_time = 0;					/* Draw time */
	bool startDone = FALSE;					/* Mote is in ready position */
	bool fireDone = FALSE;					/* Mote has fired */
	bool checkFire = FALSE;					/* Wait for fire */
	bool busy = FALSE;					/* Read accelerometer value */
	bool readyReceived = FALSE;				/* Receive READY from both motes */
	bool roundOver = FALSE;					/* Receive FIRE from both motes */
	uint8_t numberOfACKsReceived = 0;			/* Receive ACK from both motes */
	int8_t ack_node_id_0;					/* ACK received from mote 0 */
	int8_t ack_node_id_1;					/* ACK received from mote 1 */
	uint32_t t2, t3;					/* Random countdown values */
	uint16_t Node0FireTime = 0;				/* Received draw time for mote 0 */
	uint16_t Node1FireTime = 0;				/* Received draw time for mote 1 */
	Player_Stats playerStats;				/* Save player statistics */

	task void processYValues();				/* Process raw accelerometer values */
	task void ReportTime();					/* Prepare FIRE packet to be sent */
	task void sendDrawTime();				/* Send the FIRE packet */
	task void sendMessageBase();				/* Send a message to the base station */
	task void sendACK();					/* Send ACK for the START packet */
	uint16_t convertY(uint16_t data);			/* Convert raw acceleromter values */

	void reset();						/* Reset all variables and flags */
	void resetAll();					/* Reset all LEDs */

	event void Boot.booted() {
		call RadioControl.start();			/* Start the radio */
		call SysTimer.startPeriodic(1024);		/* Start the 1 second seed timer for random number generation */
	}

	event void RadioControl.startDone(error_t err) {
		call AccelTimer.startPeriodic(TIMER_PERIOD);	/* Start the timer for sampling the accelerometer */
	}
	/* read the accelerometer sensors*/
	task void ReadSensors() {
		if (call ReadY.read() != SUCCESS)
			post ReadSensors();
	}
	
	/* posts the reading of the accelerometer sensors*/
	event void AccelTimer.fired() {
		post ReadSensors();
	}

	/* Gun-mote Sends a READY message to the control mote, sets off beep to let user know they're about to start*/
	event void StartTimer.fired() {
		quick_message *payload;

		payload = (quick_message *)call Packet.getPayload(&buf_base, sizeof(quick_message));
		payload->id = TOS_NODE_ID;
		payload->messageType = READY;
		post sendMessageBase();

		startDone = TRUE;
		call Mts300Sounder.beep(100);
	}

	/* 
	   countDown is incremented for # of intervals we've passed through
	   if countDown < 3: begin CountDownTimer on another random interval for the next beep
	   if countDown == 3, make a long beep, and enter the "fire" sequence 
		(i.e. when the person moves from gun pointed downward to gun pointing at other person)   
	*/
	event void CountDownTimer.fired() {
		if ( ++countDown >= 3 ) {
			call Mts300Sounder.beep(500);
			call CountDownTimer.stop();
			call DrawTimer.startPeriodic(1);
			call Leds.led2On();
			checkFire = TRUE;
		} else if (countDown == 1) {
			call Mts300Sounder.beep(100);
			call CountDownTimer.startOneShot(t2);
		} else if (countDown == 2) {
			call Mts300Sounder.beep(100);
			call CountDownTimer.startOneShot(t3);
		}
	}
	/*
		Condition: we've been in the correct 'fire' position for .5 seconds, 
		action: send the time to the control-mote
			make a long beep
			turn led0 on.
			reset all variables
	*/
	event void FireTimer.fired() {
		call DrawTimer.stop();
		call Mts300Sounder.beep(1000);
		call Leds.led0On();
		checkFire = FALSE;
		startDone = FALSE;
		fireDone = TRUE;
		post ReportTime();
	}
	/*
		Counter for how long we take (in milliseconds) between the end of the start sequence and the fire sequence.
		Fired off 1024 times in a second.
	*/
	event void DrawTimer.fired() {
		draw_time ++;
	}

	/*
		Event for after the accelerometer reading is done.
		Stores off the accelerometer value inside accelValues.y
		calls task to perform post-processing on that value.
	*/
	event void ReadY.readDone(error_t result, uint16_t val) {
		if (result != SUCCESS) {
			post ReadSensors();
			return;
		}

		accelValues.y = val;
		post processYValues();
	}

	/*
		Fills the payload with draw time information:
			1. payload->time: time it took for mote to get to fire position
			2. payload->id: node id of the mote
			3. payload->messageType: fire message, meaning this is our 'fire' packet
		Posts the task to the packet to the control-mote
	*/

	task void ReportTime() {
		quick_message *payload;
		payload = (quick_message *)call Packet.getPayload(&buf_draw, sizeof(quick_message));
		payload->time = draw_time;
		payload->id = TOS_NODE_ID;
		payload->messageType = FIRE;
		draw_time = 0;
		post sendDrawTime();
	}
	/*
		sends the draw time from the gun-mote to the control mote
		loops until successful.
	*/

	task void sendDrawTime() {
		if (call AMSend.send(2, &buf_draw, sizeof(quick_message)) != SUCCESS)
			post sendDrawTime();
	}

	/*
		sends the READY message from a gun-mote to the control mote
		loops until successful.
	*/

	task void sendMessageBase() {
		if (call AMSend.send(2, &buf_base, sizeof(quick_message)) != SUCCESS)
			post sendMessageBase();
	}

	/*
		sends the READY message from a gun-mote to the control mote
		loops until successful.
	*/
	task void sendACK()
	{
		if (call AMSend.send(2, &buf_ack, sizeof(quick_message)) != SUCCESS)
			post sendACK();
	}

	/*
		broadcasts a START message from the control mote to the gun-motes
		loops until successful.
	*/
	task void sendMessageAll() {
		if (call AMSend.send(AM_BROADCAST_ADDR, &buf_all, sizeof(quick_message)) != SUCCESS)
			post sendMessageAll();
	}


	event void SysTimer.fired() {}

	/*
		Makes sure both gun-motes have checked in after receiving a READY packet.
		Run only from the control-mote.
	*/
	event void ACKTimer.fired() {
		quick_message *payload;

		if(numberOfACKsReceived < 2)
		{
			payload = (quick_message *)call Packet.getPayload(&buf_all, sizeof(quick_message));
			payload->id = TOS_NODE_ID;
			payload->messageType = STOP;
			post sendMessageAll();
			readyReceived = FALSE;
			if(ack_node_id_0 == -1)
			{
				printf ("Did NOT receive ACK from %s, resetting...\n", "Dan");
			}
			if (ack_node_id_1 == -1)
			{
				printf ("Did NOT receive ACK from %s, resetting...\n", "Cronin");
			}
			printfflush();
			resetAll();
		}
		
	}
	/*
		Sends out the random time intervals between each beep to the gun-motes.
	*/
	task void sendMessageRef() {
		if (call AMSend.send(AM_BROADCAST_ADDR, &buf_ref, sizeof(quick_message)) != SUCCESS)
			post sendMessageRef();
	}

	/*
		applies logic to the accelerometer readings we've taken.
		If the mote isn't in the countdown sequence, we wait until the angle is between 65 and 90 degrees
			If it is, we start a 1-second countdown.
		If the mote has initiated the countdown, we confirm that the mote doesn't move
			If the gun-mote moves, it sends off a STOP message to the other 2 motes
		If the countdown sequence is finished, we check to see if we are in 'firing' position ( 0 <= angle <= 15)
	*/
	task void processYValues() {
		uint16_t y_angle;
		
		y_angle = convertY(accelValues.y);
		
		if (y_angle == (uint16_t)NULL)
			return;

		/* If the mote is in the READY position start the StartTimer */
		if (y_angle >= 65 && y_angle <= 90) {
			/* If the StartTimer is not already running and the 1 second interval has not passed restart the StartTimer */
			if ( ! call StartTimer.isRunning() && !startDone )
				call StartTimer.startOneShot(1024);
		/* If the countdown sequence is done and the mote is in the FIRE position start the FireTimer */
		} else if ((checkFire || fireDone) && y_angle >=0 && y_angle <= 15) {
			/* If the FireTimer is not running and has not completed it's period restart it */
			if (!call FireTimer.isRunning() && !fireDone)
				call FireTimer.startOneShot(512);
		/* If the mote is not in READY or FIRE position and we haven't completed the FireTimer send STOP to the other mote and
			the base station and reset all timers, variables and flags */
		} else if (!checkFire && !fireDone) {
			quick_message *payload;
			if (startDone) {
				payload = (quick_message *)call Packet.getPayload(&buf_all, sizeof(quick_message));
				payload->id = TOS_NODE_ID;
				payload->messageType = STOP;
				post sendMessageAll();
			}
			resetAll();
		/* Otherwise if the countdown has completed but not the FireTimer reset everything but the LEDs,
			this ensures that the LEDs stay lit during the drawing state */
		} else if (!checkFire) {
			reset();
		}
	}

	/*
		If we fail in our send, repost the correct message.
	*/

	event void AMSend.sendDone(message_t *msg, error_t err) {
		if(err != SUCCESS) {
			if(msg == &buf_all)
				post sendMessageAll();
			else if(msg == &buf_base)
				post sendMessageBase();
			else if(msg == &buf_draw)
				post sendDrawTime();
			else if(msg == &buf_ref)
				post sendMessageRef();
			else if(msg == &buf_ack)
				post sendACK();
		}
	}

	/*
		resets all variables used to progress through the states of the game.
	*/
	void reset() {
		call StartTimer.stop();
		call FireTimer.stop();
		call CountDownTimer.stop();
		call DrawTimer.stop();
		startDone = FALSE;
		fireDone = FALSE;
		countDown = 0;
		roundOver = FALSE;
	}

	/*
		turns off all the LEDs and resets all variables.
	*/
	void resetAll() {
		call Leds.led0Off();
		call Leds.led1Off();
		call Leds.led2Off();
		reset();
	}


	/*
		Message processing for each of the motes.  Determines functionality by the TOS_NODE_ID.
		2 is always the control-mote, 0 and 1 are the gun-motes
		Message types:
			START: only received by gun-motes.  Pulls out 3 random time intervals
				Turns on 1st LED.
			STOP: only received by gun-motes.  Resets all variables, going back to initial state.
			READY: only received by control-mote.  Tells us which gun-mote is ready, we then wait for the other one.
					If both motes have checked in, we send out START command to gun-motes with randomized variables.
						And start ACKTimer to make sure both motes are still there.
			FIRE: Received only by control-mote.  Stores off timing information and determines winner.
					Transmits player stats to the database via printf() with '$' as the first symbol
	*/
	event message_t * Receive.receive(message_t *msg, void *payload, uint8_t len) { 
		quick_message *payload_out;
		quick_message *payload_in = (quick_message *)payload;
		
		payload_out = (quick_message *)call Packet.getPayload(&buf_ref, sizeof(quick_message));

		call Leds.led2Toggle();

		/* Check if the current mote is a gun-mote or the base station */
		if (TOS_NODE_ID < 2) {
			/* Gun-mote section to respond to a START packet */
			if (payload_in->messageType == START) {
				payload_out = (quick_message *)call Packet.getPayload(&buf_ack, sizeof(quick_message));
				payload_out->id = TOS_NODE_ID;
				payload_out->messageType = ACK;
				post sendACK();
				call CountDownTimer.startOneShot((uint32_t)payload_in->t1 * 1231);
				t2 = payload_in->t2 * 1231;
				t3 = payload_in->t3 * 1231;
				call Leds.led1On();
			/* Respond to a STOP packet */
			} else if (payload_in->messageType == STOP) {
				resetAll();
			}
		/* Base station section */
		} else {
			/* Respond to a READY packet */
			if (payload_in->messageType == READY) {
				printf ("Received Ready from %s(%i)\n", (payload_in->id)? "Cronin": "Dan", payload_in->id);
				printfflush();

				/* Check if this is the second READY packet */
				if (readyReceived) {
					ack_node_id_0 = -1;
					ack_node_id_1 = -1;
					Node0FireTime = 0;
					Node1FireTime = 0;
					payload_out->id = TOS_NODE_ID;
					payload_out->messageType = START;
					payload_out->t1 = (call Random.rand16()>>14) + 1;
					payload_out->t2 = (call Random.rand16()>>14) + 1;
					payload_out->t3 = (call Random.rand16()>>14) + 1;

					numberOfACKsReceived = 0;
					call ACKTimer.startOneShot(1536); // 1.5 secs to make sure both motes ACK the START packet
					post sendMessageRef();
					readyReceived = FALSE;
					call ParameterInit.init((uint16_t)call SysTimer.getNow());
				} else
					readyReceived = TRUE;
			/* Respond to a FIRE packet */
			} else if (payload_in->messageType == FIRE) {
				/* Check which motes sent the FIRE packet and store their draw time */
				if(payload_in->id == 0)
				{
					Node0FireTime = payload_in->time;
				}
				else if(payload_in->id == 1)
				{
					Node1FireTime = payload_in->time;
				}
				printf("%s's Draw Time = %i ms\n", (payload_in->id)? "Cronin": "Dan", payload_in->time);
				/* When both motes have sent a FIRE packet determine the winner */
				if(Node1FireTime != 0 && Node0FireTime != 0)
				{
					roundOver = TRUE;
					if(Node0FireTime < Node1FireTime)
					{
						printf("Dan (node 0) wins!\n");
						playerStats.winnerId = 0;
					}
					else if(Node1FireTime < Node0FireTime)
					{
						printf("Cronin (node 1) wins!\n");
						playerStats.winnerId = 1;
					}
					else
					{
						printf("The match is a draw!\n");
						playerStats.winnerId = -1;
					}
					playerStats.p0DrawTime = Node0FireTime;
					playerStats.p1DrawTime = Node1FireTime;

				}
				printfflush();

				/* Special message to be inserted into the database */
				if (roundOver) {
					printf("$ 0 %ld %i %i\n", playerStats.p0DrawTime, (playerStats.winnerId)? 0:1, (playerStats.winnerId == -1)? 1:0);
					printfflush();
					printf("$ 1 %ld %i %i\n", playerStats.p1DrawTime, (playerStats.winnerId)? 1:0, (playerStats.winnerId == -1)? 1:0);
					printfflush();
				}
			/* Respond to a STOP packet */
			} else if (payload_in->messageType ==  STOP) {
				printf("%s(%i) messed up, starting over!\n", (payload_in->id)? "Cronin": "Dan", payload_in->id);
				printfflush();
				readyReceived = FALSE;
			}
			/* Respond to an ACK packet */
			else if (payload_in->messageType == ACK) {
				printf("%s(%i) has sent an ACK\n", (payload_in->id)? "Cronin": "Dan", payload_in->id);
				printfflush();
				++numberOfACKsReceived;
				if(payload_in->id)
				{
					ack_node_id_1 = 1;
				}
				else
				{
					ack_node_id_0 = 1;
				}
			}
		}

		return msg;
	}

	event void RadioControl.stopDone(error_t err) {}

	/*
		locks on a critical section b/c this function is called so often (every ~.02seconds, or 21 hertz)
		then translates the raw accelerometer values into angles that we can use.
	*/
	uint16_t convertY(uint16_t data) {
		float scale_factor, reading;
		int16_t accel_data = data;
		/* Obtain the calibration values for the current mote */
		int16_t y_neg_1g = (TOS_NODE_ID)? NODE1_Y_NEG_1G : NODE0_Y_NEG_1G;
		int16_t y_pos_1g = (TOS_NODE_ID)? NODE1_Y_POS_1G : NODE0_Y_POS_1G;
		bool local_busy = FALSE;

		atomic {
			local_busy = busy;
			busy = TRUE;
		}

		if (local_busy) {
			return (uint16_t)NULL;
		}

		/* Compute the scale factor */
		scale_factor = ((float)(y_pos_1g - y_neg_1g) / 2.0);

		/* Convert the raw data into g units */
		reading = 1.0 - fabs((float)(y_pos_1g - accel_data) / scale_factor);

		if ( reading < -1.0 || reading > 1.0) {
			busy = FALSE;
			return (uint16_t)NULL;
		}

		/* Compute the angle of the mote with respect to gravity in degrees */
		reading = asin(reading) * (180.0 / M_PI);//57.29577951;

		busy = FALSE;
		return (uint16_t)fabs(reading);
	}
}
