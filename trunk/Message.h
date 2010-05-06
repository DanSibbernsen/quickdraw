#ifndef __MESSAGE_H
#define __MESSAGE_H

enum
{
	MESSAGE = 243,

	NODE0_X_POS_1G = 547,
	NODE0_X_NEG_1G = 436,
	NODE0_Y_POS_1G = 580,
	NODE0_Y_NEG_1G = 474,

	NODE1_X_POS_1G = 551,
	NODE1_X_NEG_1G = 440,
	NODE1_Y_POS_1G = 573,
	NODE1_Y_NEG_1G = 462,

	TIMER_PERIOD = 21
};

typedef nx_struct message
{
	nx_uint8_t id; /* id of the mote we're on */
	nx_uint8_t messageType;/* maps to message_type enum */
	nx_uint16_t time; /* time the mote took to fire*/
	nx_uint8_t t1; /* 1st random interval*/
	nx_uint8_t t2;/* 2nd random interval*/
	nx_uint8_t t3;/* 3rd random interval*/
} quick_message;

typedef nx_struct playerStats
{
	nx_int8_t  winnerId; /* node id of the winner */
	nx_uint32_t p0DrawTime; /* node 0 draw time */
	nx_uint32_t p1DrawTime; /* node 1 draw time*/
} Player_Stats;


typedef enum
{
	READY = 0, //mote is facing downward, we are ready for countdown (between gun-mote and control-mote)
	START = 1, //motes are ready, GO!  This is only sent by the control-mote
	STOP = 2, //somebody was dumb or cheated, stop the game (between 2 gun-motes)
	FIRE = 3, //fire the packet.  fire it like it's hot. (between gun-mote and control-mote)
	ACK = 4
} message_type;

#endif __MESSAGE_H

