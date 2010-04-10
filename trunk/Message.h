#ifndef __MESSAGE_H
#define __MESSAGE_H

enum
{
	MESSAGE = 243,
};

typedef nx_struct demo_message
{
	nx_uint16_t lastReading;
	nx_bool axis;
} demo_message_t;

typedef nx_struct message
{
	nx_uint8_t id;
	nx_message_type messageType;
	nx_uint16_t time;
}


typedef enum
{
	READY = 0, //mote is facing downward, we are ready for countdown (between gun-mote and control-mote)
	START = 1 //motes are ready, GO!  This is only sent by the control-mote
	STOP = 2, //somebody was dumb or cheated, stop the game (between 2 gun-motes)
	FIRE = 3 //fire the packet.  fire it like it's hot. (between gun-mote and control-mote)
} nx_message_type;

#endif __MESSAGE_H

